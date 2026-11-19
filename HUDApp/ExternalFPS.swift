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
    private var foreground=true
    private var sourceLabel="CAP FPS"
    private var statusLabel="WAITING"
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
    func foregroundChanged(_ active:Bool) {
        foreground=active
        if tick != nil {
            if !active && !captureMode {layer.flushAndRemoveImage();cachedImage=nil;statusLabel="APP PAUSED";draw(nil)}
            else {update()}
        }
    }
    func selectSource(capture:Bool) {
        guard !floating && !launching else{return}
        captureMode=capture
        if tick != nil {update()}
    }
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
        groupAvailable=extensionInstalled && ScreenMetrics.probe()
        if capture && !groupAvailable {issue="Cần bản HUD đã ký đúng App Groups.";return}
        if capture && !receiving {issue="Bắt đầu truyền màn hình và đợi số FPS.";return}
        captureMode=capture
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
        let local=foreground ? InterfaceCadence.shared.hz : nil
        sourceLabel=captureMode ? "CAP FPS":"UI Hz"
        statusLabel=captureMode ? (value == nil ? "WAITING":"LIVE CAPTURE") : (local != nil ? "TOUCH LAB":(foreground ? "WAITING":"APP PAUSED"))
        guard playing else{return}
        draw(captureMode ? value : local)
    }
    private func draw(_ fps:Double?) {
        if layer.status == .failed {layer.flush()}
        guard layer.isReadyForMoreMediaData,let pool=pool else{return}
        var pixel:CVPixelBuffer?
        let aux=[kCVPixelBufferPoolAllocationThresholdKey as String:4] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault,pool,aux,&pixel)==kCVReturnSuccess,let pixel=pixel else{return}
        let number=fps.map{String(format:"%.0f",$0)} ?? "—"
        let status=statusLabel
        let key=number+"|"+status+"|"+sourceLabel+"|"+String(rainbow)
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
                (sourceLabel as NSString).draw(in:CGRect(x:274,y:65,width:168,height:55),withAttributes:[.font:UIFont.systemFont(ofSize:sourceLabel.count>5 ? 34:42,weight:.bold),.foregroundColor:UIColor.white])
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
    @ObservedObject private var cadence=InterfaceCadence.shared
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("prism.rainbow") private var rainbow=true
    @AppStorage("pulse.interface.enabled") private var interfaceEnabled=true
    @State private var details=false
    @State private var screenMode=false
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:15) {
                Text("PULSE / 10.0").font(.caption.monospaced().bold()).tracking(3).foregroundStyle(.cyan)
                Text("Live monitor").font(.system(size:38,weight:.bold,design:.rounded))
                Text("Hai nguồn đo độc lập").font(.subheadline).foregroundStyle(.secondary)
                GlassPanel {
                    HStack {
                        Text(screenMode ? "CAPTURE FPS":"UI Hz").font(.caption.monospaced().bold()).tracking(1.5)
                        Spacer()
                        Label(monitor.floating ? "PiP ON":"PREVIEW",systemImage:monitor.floating ? "circle.fill":"circle").font(.caption2.monospaced()).foregroundStyle(.cyan)
                    }
                    PreviewSurface(monitor:monitor).aspectRatio(480.0/216.0,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:17))
                    Picker("Nguồn đo",selection:$screenMode) {
                        Text("Touch Lab").tag(false)
                        Text("Ngoài app").tag(true)
                    }.pickerStyle(.segmented).disabled(monitor.floating || monitor.launching)
                    Text(screenMode ? "Đếm khung hình ReplayKit. Không phải FPS render của game." : "Nhịp callback giao diện Touch Lab. Không ghi màn hình. Dừng khi ra ngoài app.").font(.caption).foregroundStyle(.secondary)
                    if screenMode {
                        if monitor.extensionInstalled && monitor.groupAvailable {
                            HStack {
                                VStack(alignment:.leading,spacing:5) {
                                    Text("1 · Bắt đầu truyền").font(.headline)
                                    Text("Chọn Touch Lab FPS Capture, tắt mic.").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer();ScreenPicker().frame(width:54,height:54)
                            }
                            Text(monitor.state).font(.caption).foregroundStyle(monitor.receiving ? Color.mint:Color.secondary)
                        } else {
                            Text(monitor.extensionInstalled ? "Thiếu App Groups trong chữ ký. Ký app và extension bằng profile hợp lệ." : "Bản Pro/Lite không có ReplayKit extension. Cài HUD 10 để đo ngoài app.").font(.subheadline).foregroundStyle(.orange)
                        }
                    }
                    Button {monitor.start(capture:screenMode)} label:{
                        Label(monitor.launching ? "Đang kết nối…" : (monitor.floating ? "PiP đang mở":"Mở cửa sổ nổi"),systemImage:"pip.enter")
                    }.buttonStyle(PulsePrimary()).disabled(monitor.launching || monitor.floating || !AVPictureInPictureController.isPictureInPictureSupported() || (screenMode && !monitor.receiving) || (!screenMode && cadence.hz == nil))
                    if monitor.floating || monitor.launching {
                        Button("Đóng cửa sổ nổi",role:.destructive){monitor.stop()}.frame(maxWidth:.infinity)
                    }
                    Toggle("Viền Rainbow",isOn:$rainbow)
                    Toggle("Đo nhịp giao diện",isOn:$interfaceEnabled)
                }
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                    Tile(label:"Nhịp Touch Lab",value:cadence.hz.map{String(format:"%.1f Hz",$0)} ?? "—")
                    Tile(label:"Capture FPS",value:monitor.fps.map{String(format:"%.1f",$0)} ?? "—")
                    Tile(label:"P95 UI · ms",value:cadence.p95.map{String(format:"%.1f",$0)} ?? "—")
                    Tile(label:"P95 Capture · ms",value:monitor.frameP95.map{String(format:"%.1f",$0)} ?? "—")
                }
                GlassPanel {
                    DisclosureGroup(isExpanded:$details) {
                        check("PiP hỗ trợ",AVPictureInPictureController.isPictureInPictureSupported())
                        check("PiP sẵn sàng",monitor.possible)
                        check("ReplayKit extension",monitor.extensionInstalled)
                        check("App Groups",monitor.groupAvailable)
                        check("Mẫu capture mới",monitor.receiving)
                    } label:{Text("Chẩn đoán kết nối").font(.headline)}
                }
                if let issue=monitor.issue{Text(issue).font(.caption).foregroundStyle(.orange).textSelection(.enabled)}
                Text("Khi ra ngoài app, chỉ chế độ Capture có dữ liệu nếu broadcast chạy và iOS cho phép. Dừng truyền trong Trung tâm điều khiển khi dùng xong. Không lưu hoặc gửi hình ảnh.").font(.caption).foregroundStyle(.secondary)
            }.padding(18)
        }.background(LabBackdrop()).toolbar(.hidden,for:.navigationBar)
        .onAppear {
            monitor.rainbow=rainbow;monitor.prepare()
            if monitor.floating {screenMode=monitor.captureMode}
            else {screenMode=monitor.extensionInstalled && monitor.groupAvailable;monitor.selectSource(capture:screenMode)}
        }
        .onDisappear {monitor.leavePreview()}
        .onChange(of:screenMode){_,v in monitor.selectSource(capture:v)}
        .onChange(of:rainbow){_,v in monitor.rainbow=v}
        .onChange(of:phase){_,v in if v == .active {monitor.prepare()}}
        .animation(reduceMotion ? nil : .spring(response:0.28,dampingFraction:0.82),value:screenMode)
    }
    func check(_ title:String,_ yes:Bool)->some View {
        HStack {Image(systemName:yes ? "checkmark.circle.fill":"circle.dashed").foregroundStyle(yes ? Color.mint:Color.secondary);Text(title).font(.subheadline);Spacer();Text(yes ? "OK":"—").font(.caption.monospaced())}.padding(.top,5)
    }
}
