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
    private let width=240,height=112
    @Published private(set) var groupAvailable=false
    func prepare() {
        guard tick==nil else{return}
        issue=nil
        groupAvailable=ScreenMetrics.probe()
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
    func start() {
        issue=nil
        guard groupAvailable else {issue="App Groups chưa được cấp quyền trong chữ ký.";return}
        guard extensionInstalled else {issue="Thiếu extension ReplayKit trong IPA sau khi ký.";return}
        guard receiving else {issue="Chưa có mẫu từ ReplayKit. Bắt đầu truyền màn hình trước.";return}
        guard let c=controller,!c.isPictureInPictureActive,!launching else{return}
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback,mode:.default,options:[.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            audioActive=true
        } catch {issue=error.localizedDescription;return}
        launching=true
        playing=true
        c.invalidatePlaybackState()
        attemptStart(c,remaining:12)
    }
    private func attemptStart(_ c:AVPictureInPictureController,remaining:Int) {
        guard launching else{return}
        if c.isPictureInPicturePossible {c.startPictureInPicture();return}
        guard remaining>0 else {launching=false;issue="PiP chưa sẵn sàng. Kiểm tra cài đặt Hình trong hình, giữ màn xem trước mở và thử lại.";deactivateAudio();return}
        DispatchQueue.main.asyncAfter(deadline:.now()+0.25){[weak self,weak c] in if let c=c {self?.attemptStart(c,remaining:remaining-1)}}
    }
    private func deactivateAudio() {
        if audioActive {try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation);audioActive=false}
    }
    func stop() {
        launching=false
        if controller?.isPictureInPictureActive==true {controller?.stopPictureInPicture()}
        else {shutdown()}
    }
    func leavePreview() {if !floating && !launching && controller?.isPictureInPictureActive != true {shutdown()}}
    private func shutdown() {
        tick?.invalidate();tick=nil
        launching=false;deactivateAudio()
        fps=nil;receiving=false;frameAge=nil;possible=controller?.isPictureInPicturePossible ?? false
        cachedImage=nil;cachedLabel=""
        layer.flushAndRemoveImage()
    }
    private func update() {
        let s=ScreenMetrics.read()
        let valid=s?.state=="live" && s?.fps != nil
        if receiving != valid {receiving=valid}
        let age=s.map{max(0,ProcessInfo.processInfo.systemUptime-$0.uptime)}
        frameAge=age
        let value=valid ? s?.fps:nil
        if fps != value {fps=value}
        let label:String
        if !groupAvailable {label="Thiếu quyền App Groups"}
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
        if cachedImage == nil || number != cachedLabel {
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
        let image=UIGraphicsImageRenderer(size:CGSize(width:width,height:height),format:format).image{_ in
            UIColor(red:0.04,green:0.05,blue:0.07,alpha:1).setFill()
            UIRectFill(CGRect(x:0,y:0,width:width,height:height))
            let style=NSMutableParagraphStyle();style.alignment = .center
            (number as NSString).draw(in:CGRect(x:0,y:5,width:width,height:67),withAttributes:[.font:UIFont.monospacedDigitSystemFont(ofSize:54,weight:.bold),.foregroundColor:UIColor.white,.paragraphStyle:style])
            ("CAP FPS" as NSString).draw(in:CGRect(x:0,y:75,width:width,height:27),withAttributes:[.font:UIFont.monospacedSystemFont(ofSize:17,weight:.semibold),.foregroundColor:fps == nil ? UIColor.lightGray:UIColor.systemMint,.paragraphStyle:style])
        }
        cachedImage=image.cgImage;cachedLabel=number
        }
        guard let cg=cachedImage else{return}
        guard CVPixelBufferLockBaseAddress(pixel,[]) == kCVReturnSuccess else{return}
        if let base=CVPixelBufferGetBaseAddress(pixel),let ctx=CGContext(data:base,width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixel),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue){
            ctx.draw(cg,in:CGRect(x:0,y:0,width:width,height:height))
        }
        CVPixelBufferUnlockBaseAddress(pixel,[])
        var desc:CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:pixel,formatDescriptionOut:&desc)==noErr,let desc=desc else{return}
        let pts=CMClockGetTime(CMClockGetHostTimeClock())
        var timing=CMSampleTimingInfo(duration:CMTime(value:1,timescale:2),presentationTimeStamp:pts,decodeTimeStamp:.invalid)
        var sample:CMSampleBuffer?
        if CMSampleBufferCreateReadyWithImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:pixel,formatDescription:desc,sampleTiming:&timing,sampleBufferOut:&sample)==noErr,let sample=sample {layer.enqueue(sample)}
    }
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController:AVPictureInPictureController){launching=false;floating=true;issue=nil}
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController:AVPictureInPictureController){floating=false;shutdown()}
    func pictureInPictureController(_ pictureInPictureController:AVPictureInPictureController,failedToStartPictureInPictureWithError error:Error){issue=error.localizedDescription;floating=false;shutdown()}
    func pictureInPictureController(_ pictureInPictureController:AVPictureInPictureController,setPlaying:Bool){playing=setPlaying;if !setPlaying{layer.flushAndRemoveImage()}else{update()};pictureInPictureController.invalidatePlaybackState()}
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController:AVPictureInPictureController)->CMTimeRange{CMTimeRange(start:.negativeInfinity,duration:.positiveInfinity)}
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
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text("TOUCH LAB / 7.0").font(.caption.bold()).tracking(3).foregroundStyle(.mint)
                Text("Live monitor").font(.system(size:35,weight:.bold,design:.rounded))
                Text("Đo khung hình màn hình qua ReplayKit").font(.subheadline).foregroundStyle(.secondary)
                GlassPanel {
                    HStack {Text("CAPTURE FPS").font(.caption.bold()).tracking(2);Spacer();Text(monitor.floating ? "PiP đang mở":"CHỜ").font(.caption.monospaced()).foregroundStyle(.mint)}
                    PreviewSurface(monitor:monitor).aspectRatio(240.0/112.0,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:14))
                    Text(monitor.state).font(.subheadline).foregroundStyle(.secondary)
                    if let age=monitor.frameAge {Text(String(format:"Tuổi mẫu %.2f giây",age)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)}
                }
                GlassPanel {
                    Text("Kiểm tra quyền").font(.headline)
                    check("Extension ReplayKit",monitor.extensionInstalled)
                    check("App Groups (đọc / ghi)",monitor.groupAvailable)
                    check("Picture-in-Picture hỗ trợ",AVPictureInPictureController.isPictureInPictureSupported())
                    check("Đã nhận mẫu capture",monitor.receiving)
                    if !monitor.groupAvailable {
                        Text("IPA đã khai báo App Groups nhưng chứng chỉ/profile phải cấp cùng group cho app và extension. Không thể tự cấp quyền từ bên trong app.").font(.caption).foregroundStyle(.orange)
                    }
                }
                GlassPanel {
                    HStack {
                        VStack(alignment:.leading,spacing:5){Text("01  Bắt đầu truyền").font(.headline);Text("Chọn Touch Lab FPS Capture và xác nhận. Không bật mic.").font(.caption).foregroundStyle(.secondary)}
                        Spacer();ScreenPicker().frame(width:54,height:54)
                    }
                    Divider()
                    Button {monitor.start()} label:{
                        HStack {Image(systemName:"pip.enter");Text(monitor.launching ? "Đang mở PiP…" : "02  Bật cửa sổ FPS");Spacer()}.padding(8)
                    }.buttonStyle(.borderedProminent).disabled(!monitor.groupAvailable || !monitor.receiving || monitor.launching || monitor.floating)
                    Text("03  Vuốt về Home, mở game.").font(.headline)
                    Button("Dừng cửa sổ nổi",role:.destructive){monitor.stop()}
                    if let issue=monitor.issue {Text(issue).font(.caption).foregroundStyle(.orange).textSelection(.enabled)}
                }
                Text("CAP FPS là tốc độ nhận khung hình ReplayKit, có thể bị ảnh hưởng bởi chính cửa sổ PiP và không phải FPS GPU của game. iOS chọn kích thước và lịch chạy; chưa bảo đảm hoạt động trên mọi máy. Chỉ xử lý timestamp, không lưu hay gửi hình/âm thanh. Dừng ghi trong Trung tâm điều khiển sau khi dùng.").font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }.background(LabBackdrop()).navigationTitle("FPS nổi").navigationBarTitleDisplayMode(.inline)
        .onAppear {lab.prepareForGame();monitor.prepare()}
        .onDisappear {monitor.leavePreview()}
    }
    func check(_ title:String,_ yes:Bool)->some View {
        HStack {Image(systemName:yes ? "checkmark.circle.fill":"exclamationmark.circle").foregroundStyle(yes ? Color.mint:Color.orange);Text(title).font(.subheadline);Spacer();Text(yes ? "OK":"Chưa").font(.caption.monospaced())}
    }
}
