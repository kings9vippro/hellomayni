import SwiftUI
import UIKit
import AVKit
import AVFoundation
import CoreVideo
import CoreMedia
import ReplayKit

final class CaptureHUD: NSObject, ObservableObject, AVPictureInPictureSampleBufferPlaybackDelegate, AVPictureInPictureControllerDelegate {
    static let shared=CaptureHUD()
    let layer=AVSampleBufferDisplayLayer()
    @Published var possible=false
    @Published var floating=false
    @Published var state="Chưa có dữ liệu"
    @Published var fps:Double?
    @Published var issue:String?
    @Published var receiving=false
    @Published var launching=false
    @Published var captureMode=true
    @Published var frameP95:Double?
    @Published var sampleCount:Int?
    @Published var rainbow=true
    private var previewVisible=false
    private var startGeneration=0
    @Published var frameAge:Double?
    private var audioActive=false
    private var cachedImage:CGImage?
    private var cachedLabel=""
    var extensionInstalled:Bool {
        guard let dir=Bundle.main.builtInPlugInsURL,let items=try? FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil) else{return false}
        return items.contains{Bundle(url:$0)?.bundleIdentifier == (Bundle.main.bundleIdentifier ?? "")+".broadcast"}
    }
    private var controller:AVPictureInPictureController?
    private var tick:Timer?
    private var observation:NSKeyValueObservation?
    private var clock:CMTimebase?
    private var pool:CVPixelBufferPool?
    private var playing=true
    private let width=480,height=216
    @Published private(set) var groupAvailable=false
    func prepare() {
        previewVisible=true
        if tick != nil {return}
        issue=nil
        groupAvailable=extensionInstalled && ScreenMetrics.probe()
        guard AVPictureInPictureController.isPictureInPictureSupported() else{issue="Máy không hỗ trợ PiP";return}
        if controller==nil {
            layer.videoGravity = .resizeAspect
            var tb:CMTimebase?
            if CMTimebaseCreateWithSourceClock(allocator:kCFAllocatorDefault,sourceClock:CMClockGetHostTimeClock(),timebaseOut:&tb)==noErr,let tb=tb {
                CMTimebaseSetTime(tb,time:CMClockGetTime(CMClockGetHostTimeClock()))
                CMTimebaseSetRate(tb,rate:1)
                layer.controlTimebase=tb;clock=tb
            }
            let source=AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer:layer,playbackDelegate:self)
            let c=AVPictureInPictureController(contentSource:source)
            controller=c;c.delegate=self;c.requiresLinearPlayback=true
            c.canStartPictureInPictureAutomaticallyFromInline=false
            observation=c.observe(\.isPictureInPicturePossible,options:[.initial,.new]) { [weak self] c,_ in
                DispatchQueue.main.async{self?.possible=c.isPictureInPicturePossible}
            }
            let attrs:[String:Any]=[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height,kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true,kCVPixelBufferIOSurfacePropertiesKey as String:[:]]
            CVPixelBufferPoolCreate(kCFAllocatorDefault,nil,attrs as CFDictionary,&pool)
        }
        playing=true
        update()
        let timer=Timer(timeInterval:0.5,repeats:true){[weak self] _ in self?.update()}
        timer.tolerance=0.06
        RunLoop.main.add(timer,forMode:.common);tick=timer
    }
    func start(capture:Bool) {
        if tick==nil {prepare()}
        issue=nil
        // Open a genuine PiP even before a capture stream is available. Never substitute synthetic FPS.
        guard let c=controller,!c.isPictureInPictureActive,!launching else{return}
        captureMode=true
        startGeneration += 1
        let generation=startGeneration
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback,mode:.default,options:[.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            audioActive=true
        } catch {issue=error.localizedDescription;return}
        launching=true
        playing=true
        c.invalidatePlaybackState()
        update()
        attemptStart(c,remaining:24,generation:generation)
    }
    private func attemptStart(_ c:AVPictureInPictureController,remaining:Int,generation:Int) {
        guard launching && generation==startGeneration else{return}
        if c.isPictureInPicturePossible {
            c.startPictureInPicture()
            DispatchQueue.main.asyncAfter(deadline:.now()+8){[weak self] in
                guard let self=self,self.launching,self.startGeneration==generation else{return}
                self.launching=false;self.issue="iOS chưa xác nhận mở PiP.";self.deactivateAudio()
            }
            return
        }
        guard remaining>0 else {launching=false;issue="PiP chưa sẵn sàng. Kiểm tra Cài đặt chung → Hình trong hình, giữ màn xem trước mở và thử lại.";deactivateAudio();return}
        DispatchQueue.main.asyncAfter(deadline:.now()+0.25){[weak self,weak c] in if let c=c {self?.attemptStart(c,remaining:remaining-1,generation:generation)}}
    }
    private func deactivateAudio() {
        if audioActive {try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation);audioActive=false}
    }
    func stop() {
        launching=false;startGeneration+=1
        if controller?.isPictureInPictureActive==true {controller?.stopPictureInPicture()}
        else {shutdown();if previewVisible{prepare()}}
    }
    func leavePreview() {
        previewVisible=false
        if !floating && !launching && controller?.isPictureInPictureActive != true {shutdown()}
    }
    private func shutdown() {
        tick?.invalidate();tick=nil
        launching=false;deactivateAudio()
        fps=nil;receiving=false;frameAge=nil;frameP95=nil;sampleCount=nil;possible=controller?.isPictureInPicturePossible ?? false
        cachedImage=nil;cachedLabel=""
        layer.flushAndRemoveImage()
    }
    private func update() {
        let s=groupAvailable ? ScreenMetrics.read() : nil
        let valid=s?.state=="live" && s?.fps != nil
        if receiving != valid {receiving=valid}
        let age=s.map{max(0,ProcessInfo.processInfo.systemUptime-$0.uptime)}
        if frameAge != age {frameAge=age}
        if frameP95 != s?.p95MS {frameP95=s?.p95MS}
        if sampleCount != s?.count {sampleCount=s?.count}
        let value=valid ? s?.fps:nil
        if fps != value {fps=value}
        let label:String
        if !extensionInstalled {label="Chỉ xem trước PiP · cần bản HUD để đo FPS"}
        else if !groupAvailable {label="Thiếu quyền App Groups cho capture"}
        else if s==nil {label="Chờ dữ liệu / đã dừng"}
        else if s?.state=="live" {label="Đang nhận mẫu màn hình"}
        else if s?.state=="paused" {label="Đang tạm dừng"}
        else if s?.state=="ended" {label="Đã kết thúc ghi"}
        else {label="Đang chờ mẫu"}
        if state != label {state=label}
        guard playing else{return}
        draw(value)
    }
    private func draw(_ fps:Double?) {
        if layer.status == .failed {layer.flush()}
        guard layer.isReadyForMoreMediaData,let pool=pool else{return}
        var pixel:CVPixelBuffer?
        let aux=[kCVPixelBufferPoolAllocationThresholdKey as String:4] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault,pool,aux,&pixel)==kCVReturnSuccess,let pixel=pixel else{return}
        let number=fps.map{String(format:"%.0f",$0)} ?? "—"
        let status=fps != nil ? "LIVE CAPTURE" : (groupAvailable ? "WAITING" : "NO SOURCE")
        let key=number+"|"+status+"|"+String(rainbow)
        if cachedImage == nil || key != cachedLabel {
            let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
            let image=UIGraphicsImageRenderer(size:CGSize(width:width,height:height),format:format).image{renderer in
                let ctx=renderer.cgContext
                UIColor(red:0.035,green:0.045,blue:0.075,alpha:1).setFill()
                UIRectFill(CGRect(x:0,y:0,width:width,height:height))
                let colors=[UIColor.systemPink,UIColor.systemOrange,UIColor.systemYellow,UIColor.systemMint,UIColor.systemCyan,UIColor.systemPurple].map{$0.cgColor}
                if rainbow,let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors as CFArray,locations:nil) {
                    ctx.saveGState()
                    ctx.addPath(UIBezierPath(roundedRect:CGRect(x:12,y:12,width:456,height:192),cornerRadius:25).cgPath)
                    ctx.setLineWidth(6);ctx.replacePathWithStrokedPath();ctx.clip()
                    ctx.drawLinearGradient(gradient,start:CGPoint(x:10,y:10),end:CGPoint(x:470,y:206),options:[])
                    ctx.restoreGState()
                } else {
                    UIColor.systemMint.setStroke()
                    let outline=UIBezierPath(roundedRect:CGRect(x:12,y:12,width:456,height:192),cornerRadius:25)
                    outline.lineWidth=4;outline.stroke()
                }
                (number as NSString).draw(in:CGRect(x:34,y:38,width:230,height:142),withAttributes:[.font:UIFont.monospacedDigitSystemFont(ofSize:104,weight:.heavy),.foregroundColor:UIColor.white])
                ("FPS" as NSString).draw(in:CGRect(x:274,y:65,width:168,height:55),withAttributes:[.font:UIFont.systemFont(ofSize:42,weight:.bold),.foregroundColor:UIColor.white])
                (status as NSString).draw(in:CGRect(x:274,y:124,width:182,height:30),withAttributes:[.font:UIFont.monospacedSystemFont(ofSize:19,weight:.semibold),.foregroundColor:fps == nil ? UIColor.lightGray:UIColor.systemMint])
            }
            cachedImage=image.cgImage;cachedLabel=key
        }
        guard let cg=cachedImage else{return}
        guard CVPixelBufferLockBaseAddress(pixel,[]) == kCVReturnSuccess else{return}
        if let base=CVPixelBufferGetBaseAddress(pixel),let ctx=CGContext(data:base,width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixel),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue){
            ctx.draw(cg,in:CGRect(x:0,y:0,width:width,height:height))
        }
        CVPixelBufferUnlockBaseAddress(pixel,[])
        var desc:CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:pixel,formatDescriptionOut:&desc)==noErr,let desc=desc else{return}
        let pts=CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()),CMTime(value:1,timescale:20))
        var timing=CMSampleTimingInfo(duration:CMTime(value:1,timescale:2),presentationTimeStamp:pts,decodeTimeStamp:.invalid)
        var sample:CMSampleBuffer?
        if CMSampleBufferCreateReadyWithImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:pixel,formatDescription:desc,sampleTiming:&timing,sampleBufferOut:&sample)==noErr,let sample=sample {layer.enqueue(sample)}
    }
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController:AVPictureInPictureController){launching=false;floating=true;issue=nil}
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController:AVPictureInPictureController){floating=false;shutdown();if previewVisible{prepare()}}
    func pictureInPictureController(_ pictureInPictureController:AVPictureInPictureController,failedToStartPictureInPictureWithError error:Error){issue=error.localizedDescription;floating=false;shutdown()}
    func pictureInPictureController(_ pictureInPictureController:AVPictureInPictureController,setPlaying:Bool){playing=setPlaying;if setPlaying{update()};pictureInPictureController.invalidatePlaybackState()}
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController:AVPictureInPictureController)->CMTimeRange{CMTimeRange(start:.zero,duration:.positiveInfinity)}
    func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ pictureInPictureController:AVPictureInPictureController)->Bool {false}
    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController:AVPictureInPictureController)->Bool{!playing}
    func pictureInPictureController(_ pictureInPictureController:AVPictureInPictureController,didTransitionToRenderSize newRenderSize:CMVideoDimensions){}
    func pictureInPictureController(_ pictureInPictureController:AVPictureInPictureController,skipByInterval skipInterval:CMTime,completion completionHandler:@escaping ()->Void){completionHandler()}
}
final class HUDPreview:UIView {
    weak var shownLayer:AVSampleBufferDisplayLayer?
    override func layoutSubviews(){super.layoutSubviews();shownLayer?.frame=bounds}
}
struct PreviewSurface:UIViewRepresentable {
    let monitor:CaptureHUD
    func makeUIView(context:Context)->HUDPreview{
        let view=HUDPreview();view.backgroundColor = .black
        view.shownLayer=monitor.layer;view.layer.addSublayer(monitor.layer)
        return view
    }
    func updateUIView(_ uiView:HUDPreview,context:Context){monitor.layer.frame=uiView.bounds}
}
struct ScreenPicker:UIViewRepresentable {
    func makeUIView(context:Context)->RPSystemBroadcastPickerView {
        let v=RPSystemBroadcastPickerView(frame:.zero)
        v.preferredExtension=(Bundle.main.bundleIdentifier ?? "com.touchlab.optimizer.hud")+".broadcast"
        v.showsMicrophoneButton=false
        return v
    }
    func updateUIView(_ uiView:RPSystemBroadcastPickerView,context:Context){}
}
struct ExternalFPSView:View {
    @ObservedObject var lab:Lab
    @StateObject private var monitor=CaptureHUD.shared
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("prism.rainbow") private var rainbow=true
    @State private var details=false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text("TOUCH LAB  /  09").font(.caption.bold().monospaced()).tracking(3).foregroundStyle(.mint)
                Text("Live monitor").font(.system(size:38,weight:.bold,design:.rounded))
                Text("FPS nổi · Prism edition").font(.subheadline).foregroundStyle(.secondary)
                GlassPanel {
                    VStack(alignment:.leading,spacing:14) {
                        HStack {
                            Label(monitor.receiving ? "LIVE CAPTURE":"CHỜ NGUỒN",systemImage:monitor.receiving ? "waveform":"circle.dashed").font(.caption.bold()).foregroundStyle(monitor.receiving ? Color.mint:Color.secondary)
                            Spacer()
                            Text(monitor.floating ? "PiP ON":"PREVIEW").font(.caption.monospaced())
                        }
                        PreviewSurface(monitor:monitor).aspectRatio(480.0/216.0,contentMode:.fit).frame(maxWidth:280).clipShape(RoundedRectangle(cornerRadius:16)).frame(maxWidth:.infinity)
                        Text(monitor.state).font(.caption).foregroundStyle(.secondary)
                        Button {
                            monitor.start(capture:true)
                        } label:{
                            Label(monitor.launching ? "Đang mở…" : (monitor.floating ? "PiP đang hoạt động":"Mở FPS nổi"),systemImage:"pip.enter")
                                .font(.headline).frame(maxWidth:.infinity).padding(14).foregroundStyle(.black).background(Color.mint,in:RoundedRectangle(cornerRadius:16))
                        }.buttonStyle(LabPressStyle()).disabled(monitor.launching || monitor.floating || !AVPictureInPictureController.isPictureInPictureSupported())
                        Toggle("Viền Rainbow",isOn:$rainbow)
                        Text("Thu nhỏ bằng hai ngón tay trên khung PiP; iOS quyết định kích thước nhỏ nhất.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if monitor.extensionInstalled && monitor.groupAvailable {
                    GlassPanel {
                        HStack {
                            VStack(alignment:.leading,spacing:5) {
                                Text("Nguồn dữ liệu trực tiếp").font(.headline)
                                Text("Bắt đầu truyền Touch Lab FPS Capture.").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer();ScreenPicker().frame(width:54,height:54)
                        }
                        LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                            Tile(label:"Capture FPS",value:monitor.fps.map{String(format:"%.1f",$0)} ?? "—")
                            Tile(label:"P95 khung · ms",value:monitor.frameP95.map{String(format:"%.1f",$0)} ?? "—")
                            Tile(label:"Mẫu trong cửa sổ",value:monitor.sampleCount.map{String($0)} ?? "—")
                            Tile(label:"Tuổi mẫu · s",value:monitor.frameAge.map{String(format:"%.1f",$0)} ?? "—")
                        }
                    }
                } else {
                    GlassPanel {
                        Label("Chưa có nguồn FPS",systemImage:"waveform.slash").font(.headline)
                        Text(monitor.extensionInstalled ? "App và extension cần cùng App Group được cấp trong provisioning profile." : "Bản Pro/Lite mở được PiP, nhưng chỉ bản HUD có extension ReplayKit. Không hiển thị FPS ước đoán.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                GlassPanel {
                    DisclosureGroup(isExpanded:$details) {
                        check("PiP hỗ trợ",AVPictureInPictureController.isPictureInPictureSupported())
                        check("PiP sẵn sàng",monitor.possible)
                        check("ReplayKit",monitor.extensionInstalled)
                        check("App Groups",monitor.groupAvailable)
                        check("Dữ liệu mới",monitor.receiving)
                    } label:{Text("Chẩn đoán kết nối").font(.headline)}
                }
                if monitor.floating || monitor.launching {
                    Button("Đóng FPS nổi",role:.destructive){monitor.stop()}.buttonStyle(.bordered).frame(maxWidth:.infinity)
                }
                if let issue=monitor.issue{Text(issue).font(.caption).foregroundStyle(.orange).textSelection(.enabled)}
                Text("CAP FPS đo nhịp khung hình ReplayKit, không phải FPS render của Free Fire. Capture và PiP có thể gây thêm tải. Dừng truyền màn hình tại Trung tâm điều khiển khi không dùng.").font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }.background(LabBackdrop()).navigationTitle("FPS nổi").navigationBarTitleDisplayMode(.inline)
        .onAppear {lab.prepareForGame();monitor.rainbow=rainbow;monitor.prepare()}
        .onDisappear {monitor.leavePreview()}
        .onChange(of:rainbow){_,v in monitor.rainbow=v}
        .onChange(of:phase){_,v in if v == .active {monitor.prepare()}}
        .animation(reduceMotion ? nil : .spring(response:0.27,dampingFraction:0.84),value:monitor.floating)
    }
    func check(_ title:String,_ yes:Bool)->some View {
        HStack {Image(systemName:yes ? "checkmark.circle.fill":"circle.dashed").foregroundStyle(yes ? Color.mint:Color.secondary);Text(title).font(.subheadline);Spacer();Text(yes ? "OK":"—").font(.caption.monospaced())}.padding(.top,5)
    }
}
