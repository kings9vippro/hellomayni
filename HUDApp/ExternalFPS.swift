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
    private var controller:AVPictureInPictureController?
    private var tick:Timer?
    private var observation:NSKeyValueObservation?
    private var clock:CMTimebase?
    private var pool:CVPixelBufferPool?
    private var playing=true
    private let width=240,height=112
    var groupAvailable:Bool { ScreenMetrics.url != nil }
    func prepare() {
        guard tick==nil else{return}
        guard AVPictureInPictureController.isPictureInPictureSupported() else{state="Máy không hỗ trợ PiP";return}
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
        RunLoop.main.add(timer,forMode:.common);tick=timer
    }
    func start() {
        guard groupAvailable else {state="Thiếu quyền App Groups";return}
        guard let c=controller,c.isPictureInPicturePossible else{state="PiP chưa sẵn sàng";return}
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback,mode:.default,options:[.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {state=error.localizedDescription;return}
        c.startPictureInPicture()
    }
    func stop() {
        if controller?.isPictureInPictureActive==true {controller?.stopPictureInPicture()}
        else {shutdown()}
    }
    func leavePreview() {if !floating && controller?.isPictureInPictureActive != true {shutdown()}}
    private func shutdown() {
        tick?.invalidate();tick=nil
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
        fps=nil;possible=controller?.isPictureInPicturePossible ?? false
    }
    private func update() {
        let s=ScreenMetrics.read()
        let valid=groupAvailable && s?.state=="live"
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
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
        let image=UIGraphicsImageRenderer(size:CGSize(width:width,height:height),format:format).image{_ in
            UIColor(red:0.04,green:0.05,blue:0.07,alpha:1).setFill()
            UIRectFill(CGRect(x:0,y:0,width:width,height:height))
            let number=fps.map{String(format:"%.0f",$0)} ?? "—"
            let style=NSMutableParagraphStyle();style.alignment = .center
            (number as NSString).draw(in:CGRect(x:0,y:5,width:width,height:67),withAttributes:[.font:UIFont.monospacedDigitSystemFont(ofSize:54,weight:.bold),.foregroundColor:UIColor.white,.paragraphStyle:style])
            ("CAP FPS" as NSString).draw(in:CGRect(x:0,y:75,width:width,height:27),withAttributes:[.font:UIFont.monospacedSystemFont(ofSize:17,weight:.semibold),.foregroundColor:fps == nil ? UIColor.lightGray:UIColor.systemMint,.paragraphStyle:style])
        }
        guard let cg=image.cgImage else{return}
        CVPixelBufferLockBaseAddress(pixel,[])
        if let base=CVPixelBufferGetBaseAddress(pixel),let ctx=CGContext(data:base,width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixel),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue){
            ctx.draw(cg,in:CGRect(x:0,y:0,width:width,height:height))
        }
        CVPixelBufferUnlockBaseAddress(pixel,[])
        var desc:CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:pixel,formatDescriptionOut:&desc)==noErr,let desc=desc else{return}
        let pts=CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()),CMTime(value:1,timescale:10))
        var timing=CMSampleTimingInfo(duration:CMTime(value:1,timescale:2),presentationTimeStamp:pts,decodeTimeStamp:.invalid)
        var sample:CMSampleBuffer?
        if CMSampleBufferCreateReadyWithImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:pixel,formatDescription:desc,sampleTiming:&timing,sampleBufferOut:&sample)==noErr,let sample=sample {layer.enqueue(sample)}
    }
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController:AVPictureInPictureController){floating=true}
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController:AVPictureInPictureController){floating=false;shutdown()}
    func pictureInPictureController(_ pictureInPictureController:AVPictureInPictureController,failedToStartPictureInPictureWithError error:Error){state=error.localizedDescription;floating=false;shutdown()}
    func pictureInPictureController(_ pictureInPictureController:AVPictureInPictureController,setPlaying:Bool){playing=setPlaying;pictureInPictureController.invalidatePlaybackState()}
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
                Text("FPS nổi").font(.largeTitle.bold())
                Text("KHUNG HÌNH THU MÀN HÌNH · THỬ NGHIỆM").font(.caption.bold()).foregroundStyle(.mint)
                PreviewSurface(monitor:monitor).aspectRatio(240.0/112.0,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:18))
                Text(monitor.state).font(.subheadline).foregroundStyle(.secondary)
                if !monitor.groupAvailable {
                    Text("Bản ký chưa có App Groups hợp lệ. Cần ký app và broadcast extension bằng cùng team và group.com.touchlab.optimizer.hud.").foregroundStyle(.orange)
                }
                GlassPanel {
                    HStack {VStack(alignment:.leading){Text("1. Bắt đầu ghi khung hình").font(.headline);Text("Chạm biểu tượng, chọn Touch Lab FPS Capture và bắt đầu truyền.").font(.caption).foregroundStyle(.secondary)};Spacer();ScreenPicker().frame(width:54,height:54)}
                    Divider()
                    Button("2. Bật khung FPS nổi"){monitor.start()}.buttonStyle(.borderedProminent).disabled(!monitor.possible || !monitor.groupAvailable)
                    Text("3. Vuốt về màn hình chính và mở game. iOS điều khiển kích thước và vị trí cửa sổ PiP.").font(.subheadline)
                    Button("Dừng cửa sổ nổi",role:.destructive){monitor.stop()}
                }
                Text("Dừng truyền màn hình từ Trung tâm điều khiển khi chơi xong. App không lưu ảnh, audio hay video; chỉ lấy timestamp các mẫu ReplayKit. CAP FPS không phải FPS GPU, có thể thấp hơn hoặc khác tốc độ dựng hình. Thu màn hình và PiP có thể tăng tải trên iPhone XR.").font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }.background(LabBackdrop()).navigationTitle("Live FPS").navigationBarTitleDisplayMode(.inline)
        .onAppear {lab.prepareForGame();monitor.prepare()}
        .onDisappear {monitor.leavePreview()}
    }
}
