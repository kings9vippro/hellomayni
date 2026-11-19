import SwiftUI
import UIKit
import QuartzCore

struct Trainer:View {
    @State private var gain=1.35
    @State private var damping=0.15
    @State private var speed=1.0
    @State private var hits=0
    @State private var attempts=0
    @State private var session=UUID()
    @Environment(\.scenePhase) private var phase
    @State private var visible=false
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                Text("TOUCH RESPONSE").font(.caption.bold()).tracking(3).foregroundStyle(.mint)
                Text("Precision lab").font(.largeTitle.bold())
                Text("Chạm và kéo tâm từ giữa màn hình, nhả tay khi trúng vòng. Độ nhạy và lọc rung chỉ tác động trong bài tập.").font(.caption).foregroundStyle(.secondary)
                HStack {Tile(label:"Trúng / lượt",value:"\(hits)/\(attempts)");Tile(label:"Độ nhạy",value:String(format:"%.2f×",gain))}
                NativeTrainer(gain:gain,damping:damping,speed:speed,active:visible && phase == .active,session:session) {success in attempts+=1;if success{hits+=1}}.frame(height:310).clipShape(RoundedRectangle(cornerRadius:20))
                GlassPanel {
                    HStack {Text("Hệ số kéo");Spacer();Text(String(format:"%.2f×",gain)).monospacedDigit()}
                    Slider(value:$gain,in:0.65...3,step:0.05)
                    HStack {Text("Lọc rung");Spacer();Text(String(format:"%.0f%%",damping*100)).monospacedDigit()}
                    Slider(value:$damping,in:0...0.65,step:0.05)
                    HStack {Text("Tốc độ mục tiêu");Spacer();Text(String(format:"%.1f×",speed)).monospacedDigit()}
                    Slider(value:$speed,in:0.5...2,step:0.1)
                    HStack {
                        Button("Nhanh") {gain=2.0;damping=0}
                        Button("Cân bằng") {gain=1.35;damping=0.15}
                        Button("Đầm") {gain=1;damping=0.35}
                    }.buttonStyle(.bordered)
                    Button("Đặt lại kết quả"){hits=0;attempts=0;session=UUID()}.buttonStyle(.borderedProminent)
                }
            }.padding(16)
        }.background(LabBackdrop()).navigationTitle("Luyện tâm")
        .onAppear{visible=true}.onDisappear{visible=false}
    }
}

struct NativeTrainer:UIViewRepresentable {
    var gain:Double
    var damping:Double
    var speed:Double
    var active:Bool
    var session:UUID
    var result:(Bool)->Void
    func makeUIView(context:Context)->AimSurface {AimSurface()}
    func updateUIView(_ view:AimSurface,context:Context){
        view.gain=CGFloat(gain);view.damping=CGFloat(damping);view.speed=speed;view.result=result
        if view.session != session {view.session=session;view.reset()}
        view.setActive(active)
    }
    static func dismantleUIView(_ view:AimSurface,coordinator:()){view.setActive(false)}
}
final class AimSurface:UIView {
    var gain:CGFloat=1.35,damping:CGFloat=0.15
    var speed=1.0,session=UUID()
    var result:((Bool)->Void)?
    private let ring=CAShapeLayer(),cross=CAShapeLayer()
    private var link:CADisplayLink?
    private var started=CACurrentMediaTime()
    private weak var finger:UITouch?
    private var previous=CGPoint.zero,aim=CGPoint.zero
    private var previousTime:Double=0
    private var target=CGPoint.zero
    override init(frame:CGRect) {
        super.init(frame:frame)
        backgroundColor=UIColor(red:0.02,green:0.04,blue:0.07,alpha:1)
        isMultipleTouchEnabled=false
        ring.bounds=CGRect(x:0,y:0,width:44,height:44);ring.path=UIBezierPath(ovalIn:ring.bounds.insetBy(dx:2,dy:2)).cgPath
        ring.strokeColor=UIColor.systemMint.cgColor;ring.fillColor=UIColor.clear.cgColor;ring.lineWidth=2
        cross.bounds=CGRect(x:0,y:0,width:16,height:16)
        let p=UIBezierPath();p.move(to:CGPoint(x:8,y:1));p.addLine(to:CGPoint(x:8,y:15));p.move(to:CGPoint(x:1,y:8));p.addLine(to:CGPoint(x:15,y:8))
        cross.path=p.cgPath;cross.strokeColor=UIColor.white.cgColor;cross.lineWidth=1.5;cross.fillColor=UIColor.clear.cgColor
        layer.addSublayer(ring);layer.addSublayer(cross)
    }
    required init?(coder:NSCoder){fatalError("init(coder:) unsupported")}
    override func layoutSubviews(){super.layoutSubviews();if finger==nil{aim=CGPoint(x:bounds.midX,y:bounds.midY)};updateLayers()}
    func reset(){finger=nil;started=CACurrentMediaTime();aim=CGPoint(x:bounds.midX,y:bounds.midY);updateLayers()}
    func setActive(_ active:Bool) {
        if !active {link?.invalidate();link=nil;finger=nil;return}
        if link != nil{return}
        let display=CADisplayLink(target:self,selector:#selector(frameTick(_:)))
        display.preferredFramesPerSecond=60
        display.add(to:.main,forMode:.common);link=display
    }
    override func didMoveToWindow(){super.didMoveToWindow();if window==nil{setActive(false)}}
    @objc private func frameTick(_ display:CADisplayLink) {
        let t=(display.timestamp-started)*speed
        target=CGPoint(x:24+max(0,bounds.width-48)*(0.5+0.44*sin(t*1.7)),y:24+max(0,bounds.height-48)*(0.5+0.39*cos(t*1.2)))
        updateLayers()
    }
    private func updateLayers() {CATransaction.begin();CATransaction.setDisableActions(true);ring.position=target;cross.position=aim;CATransaction.commit()}
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?) {
        guard finger==nil,let t=touches.first else{return}
        finger=t;previous=t.preciseLocation(in:self);previousTime=t.timestamp;aim=CGPoint(x:bounds.midX,y:bounds.midY);updateLayers()
    }
    private func track(_ t:UITouch,_ e:UIEvent?) {
        for sample in e?.coalescedTouches(for:t) ?? [t] {
            guard sample.timestamp>previousTime else{continue}
            let q=sample.preciseLocation(in:self)
            let dx=q.x-previous.x,dy=q.y-previous.y
            // Reduce small unintentional movement, retain full gain on fast flicks.
            let distance=hypot(dx,dy),factor=1-damping*max(0,1-distance/5)
            aim.x=min(bounds.width,max(0,aim.x+dx*gain*factor))
            aim.y=min(bounds.height,max(0,aim.y+dy*gain*factor))
            previous=q;previousTime=sample.timestamp
        }
        updateLayers()
    }
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent?){if let t=finger,touches.contains(t){track(t,event)}}
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?){if let t=finger,touches.contains(t){track(t,event);result?(hypot(aim.x-target.x,aim.y-target.y)<=22);finger=nil}}
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?){finger=nil}
}
