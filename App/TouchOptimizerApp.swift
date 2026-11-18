import SwiftUI
import UIKit
import MetalKit
import QuartzCore

@main struct TouchOptimizerApp: App {
    var body: some Scene { WindowGroup { MainView().preferredColorScheme(.dark) } }
}

struct Result: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var name: String
    var hz: Double
    var gap: Double
    var delay: Double
    var fps: Double
    var fingers: Int
    var samples: Int
    var rms: Double
}

final class Lab: ObservableObject {
    @Published var stats = TCStats()
    @Published var fps: Double = 0
    @Published var frameP95: Double = 0
    @Published var reset = UUID()
    @Published var prediction = true
    @Published var name = "Bản gốc"
    @Published var history: [Result] = []
    @Published var thermal = "—"
    @Published var power = false
    @Published var gpuOK = true
    init() {
        if let data = UserDefaults.standard.data(forKey:"history.v2"), let a = try? JSONDecoder().decode([Result].self,from:data) { history = a }
    }
    func save() {
        guard stats.intervals > 0 else { return }
        history.insert(Result(name:name,hz:stats.median_hz,gap:stats.p95_gap_ms,delay:stats.mean_delivery_ms,fps:fps,fingers:Int(stats.peak_fingers),samples:Int(stats.samples),rms:stats.straight_rms_pt),at:0)
        persist()
    }
    func persist() { if let d = try? JSONEncoder().encode(history) { UserDefaults.standard.set(d,forKey:"history.v2") } }
    func clear() { stats = TCStats(); reset = UUID() }
    func deviceInfo() {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "Bình thường"
        case .fair: thermal = "Ấm"
        case .serious: thermal = "Nóng"
        case .critical: thermal = "Rất nóng"
        @unknown default: thermal = "Không rõ"
        }
        power = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}

struct MainView: View {
    @StateObject private var lab = Lab()
    var body: some View {
        TabView {
            NavigationStack { Meter(lab:lab) }.tabItem { Label("Cảm ứng",systemImage:"hand.draw") }
            NavigationStack { Trainer() }.tabItem { Label("Luyện tâm",systemImage:"scope") }
            NavigationStack { History(lab:lab) }.tabItem { Label("So sánh",systemImage:"chart.bar") }
            NavigationStack { Guide() }.tabItem { Label("Tối ưu",systemImage:"slider.horizontal.3") }
        }.tint(.mint)
    }
}
struct Tile: View {
    var label:String
    var value:String
    var body:some View {
        VStack(alignment:.leading,spacing:5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title3,design:.monospaced)).fontWeight(.semibold).minimumScaleFactor(0.5).lineLimit(1)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(13).background(.thinMaterial,in:RoundedRectangle(cornerRadius:15))
    }
}
struct Meter: View {
    @ObservedObject var lab:Lab
    @Environment(\.scenePhase) private var phase
    @State private var shown = false
    func fmt(_ n:Double,_ unit:String,_ valid:Bool)->String { valid ? String(format:"%.1f %@",n,unit) : "—" }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                Text("TOUCH LAB / PRO 2.0").font(.caption.bold()).tracking(3).foregroundStyle(.mint)
                Text("Đo cảm ứng thật").font(.largeTitle.bold())
                Text("Vuốt thẳng, chạm nhiều ngón hoặc kéo nhanh. Số liệu từ UIKit và Metal.").font(.subheadline).foregroundStyle(.secondary)
                ZStack(alignment:.topTrailing) {
                    Surface(lab:lab,running:shown && phase == .active).frame(height:220).clipShape(RoundedRectangle(cornerRadius:20))
                    Text(lab.fps>0 ? String(format:"%.0f FPS",lab.fps) : "— FPS").font(.system(.caption,design:.monospaced).bold()).padding(8).background(.black.opacity(0.75),in:Capsule()).foregroundStyle(.mint).padding(9).allowsHitTesting(false)
                }
                if !lab.gpuOK { Text("Không khởi tạo được Metal. Không có số liệu FPS.").foregroundStyle(.orange) }
                Toggle("Hiển thị dự đoán điểm chạm",isOn:$lab.prediction).font(.subheadline)
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:9) {
                    Tile(label:"Tần suất mẫu nhận",value:fmt(lab.stats.median_hz,"Hz",lab.stats.intervals>0))
                    Tile(label:"Khoảng mẫu P95",value:fmt(lab.stats.p95_gap_ms,"ms",lab.stats.intervals>0))
                    Tile(label:"Trễ callback",value:fmt(lab.stats.mean_delivery_ms,"ms",lab.stats.latency_count>0))
                    Tile(label:"Ngón đồng thời tối đa",value:String(lab.stats.peak_fingers))
                    Tile(label:"Khung hình P95",value:fmt(lab.frameP95,"ms",lab.fps>0))
                    Tile(label:"Số mẫu ghi nhận",value:String(lab.stats.samples))
                    Tile(label:"Lệch đường thẳng RMS",value:fmt(lab.stats.straight_rms_pt,"pt",lab.stats.strokes>0))
                    Tile(label:"Nhiệt hệ thống",value:lab.thermal)
                    Tile(label:"Cử chỉ bị hủy",value:String(lab.stats.cancelled))
                    Tile(label:"Nguồn điện thấp",value:lab.power ? "Bật" : "Tắt")
                }
                TextField("Tên cấu hình",text:$lab.name).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Đo lại") { lab.clear() }.buttonStyle(.bordered)
                    Spacer()
                    Button("Lưu kết quả") { lab.save() }.buttonStyle(.borderedProminent).disabled(lab.stats.intervals==0)
                }
                Text("FPS là khung Metal được trình chiếu trong app này. Hz là mẫu UITouch nhận được, không phải Hz vật lý. Trễ callback không phải tổng độ trễ màn hình. Dự đoán chỉ để vẽ, không tính vào số mẫu.").font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }.background(Color(red:0.035,green:0.06,blue:0.08))
        .navigationTitle("Touch Lab").navigationBarTitleDisplayMode(.inline)
        .onAppear { shown=true; lab.deviceInfo() }.onDisappear { shown=false }
    }
}

struct Surface: UIViewRepresentable {
    @ObservedObject var lab:Lab
    var running:Bool
    func makeUIView(context:Context)->TouchMetal {
        let v=TouchMetal(frame:.zero,device:MTLCreateSystemDefaultDevice())
        v.lab=lab; v.token=lab.reset; v.isPaused = !running
        return v
    }
    func updateUIView(_ v:TouchMetal,context:Context) {
        v.lab=lab
        if v.token != lab.reset { v.token=lab.reset; v.clearSession() }
        v.setRunning(running)
    }
    static func dismantleUIView(_ v:TouchMetal,coordinator:()) { v.setRunning(false);v.delegate=nil }
}
struct Vertex {
    var p:SIMD2<Float>
    var c:SIMD4<Float>
}
final class TouchMetal: MTKView, MTKViewDelegate {
    weak var lab:Lab?
    var token=UUID()
    private let engine=tc_create()
    private var ids:[ObjectIdentifier:Int64]=[:]
    private var lastTime:[Int64:Double]=[:]
    private var paths:[Int64:[CGPoint]]=[:]
    private var future:[Int64:[CGPoint]]=[:]
    private var serial:Int64=0
    private var queue:MTLCommandQueue?
    private var pipeline:MTLRenderPipelineState?
    private var presentation:[Double]=[]
    private var lastPublish:Double=0
    private var epoch:UInt64=0
    private var lastDevice:Double=0
    private var dirty=true
    private var wanted=false
    private let palette:[SIMD4<Float>]=[SIMD4(0.2,1,0.75,1),SIMD4(0.3,0.75,1,1),SIMD4(1,0.55,0.2,1),SIMD4(1,0.35,0.65,1)]
    override init(frame:CGRect,device:MTLDevice?) {
        super.init(frame:frame,device:device)
        isMultipleTouchEnabled=true
        isOpaque=true
        colorPixelFormat = .bgra8Unorm
        clearColor=MTLClearColorMake(0.025,0.07,0.09,1)
        preferredFramesPerSecond=60
        enableSetNeedsDisplay=false
        isPaused=true
        accessibilityLabel="Vùng kiểm tra nhiều điểm chạm"
        if let device=device {
            queue=device.makeCommandQueue()
            let src="""
            #include <metal_stdlib>
            using namespace metal;
            struct V { float2 p; float4 c; };
            struct Out { float4 position [[position]]; float4 color; };
            vertex Out touch_vertex(const device V* v [[buffer(0)]],uint i [[vertex_id]]) {
              Out o; o.position=float4(v[i].p,0,1);o.color=v[i].c;return o;
            }
            fragment float4 touch_fragment(Out in [[stage_in]]) { return in.color; }
            """
            if let lib=try? device.makeLibrary(source:src,options:nil) {
                let d=MTLRenderPipelineDescriptor()
                d.vertexFunction=lib.makeFunction(name:"touch_vertex")
                d.fragmentFunction=lib.makeFunction(name:"touch_fragment")
                d.colorAttachments[0].pixelFormat=colorPixelFormat
                pipeline=try? device.makeRenderPipelineState(descriptor:d)
            }
        }
        delegate=self
    }
    required init(coder:NSCoder) { fatalError("init(coder:) unsupported") }
    deinit { tc_destroy(engine) }
    func setRunning(_ value:Bool) {
        guard value != wanted else { return }
        wanted=value;epoch &+= 1;presentation.removeAll();lastPublish=0
        isPaused = !value
        if !value {
            for id in ids.values { tc_end(engine,id,1) }
            ids.removeAll();lastTime.removeAll();future.removeAll();dirty=true
        }
        DispatchQueue.main.async { [weak self] in
            guard let self=self else{return}
            self.lab?.fps=0;self.lab?.frameP95=0;self.lab?.gpuOK=self.pipeline != nil
        }
    }
    func clearSession() { tc_reset(engine);ids.removeAll();lastTime.removeAll();paths.removeAll();future.removeAll();serial=0;dirty=true }
    func mtkView(_ view:MTKView,drawableSizeWillChange size:CGSize) {}
    private func ingest(_ t:UITouch,_ e:UIEvent?) {
        guard let id=ids[ObjectIdentifier(t)] else {return}
        let now=ProcessInfo.processInfo.systemUptime
        for s in e?.coalescedTouches(for:t) ?? [t] {
            guard s.timestamp > (lastTime[id] ?? -1) else {continue}
            lastTime[id]=s.timestamp
            let p=s.preciseLocation(in:self)
            tc_sample(engine,id,s.timestamp,Double(p.x),Double(p.y),now)
            paths[id,default:[]].append(p)
        }
        if let n=paths[id]?.count,n>500 {paths[id]?.removeFirst(n-500)}
        future[id]=(e?.predictedTouches(for:t) ?? []).map{$0.preciseLocation(in:self)}
        dirty=true
    }
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?) {
        if ids.isEmpty {paths.removeAll();future.removeAll()}
        for t in touches where t.type == .direct {serial += 1;ids[ObjectIdentifier(t)]=serial;tc_begin(engine,serial);ingest(t,event)}
    }
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent?) { for t in touches {ingest(t,event)} }
    private func finish(_ touches:Set<UITouch>,_ event:UIEvent?,_ cancelled:Bool) {
        for t in touches {ingest(t,event);if let id=ids.removeValue(forKey:ObjectIdentifier(t)) {tc_end(engine,id,cancelled ? 1:0);lastTime.removeValue(forKey:id);future.removeValue(forKey:id)}}
        dirty=true
    }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?) {finish(touches,event,false)}
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?) {finish(touches,event,true)}
    private func vertex(_ p:CGPoint,_ color:SIMD4<Float>)->Vertex {
        Vertex(p:SIMD2(Float(p.x/max(1,bounds.width)*2-1),Float(1-p.y/max(1,bounds.height)*2)),c:color)
    }
    private func render(_ vertices:[Vertex],_ encoder:MTLRenderCommandEncoder,_ primitive:MTLPrimitiveType = .lineStrip) {
        guard vertices.count>=2,let device=device else{return}
        vertices.withUnsafeBufferPointer { ptr in
            guard let base=ptr.baseAddress else{return}
            let n=ptr.count*MemoryLayout<Vertex>.stride
            if n<=4096 {encoder.setVertexBytes(base,length:n,index:0)}
            else {guard let b=device.makeBuffer(bytes:base,length:n,options:.storageModeShared) else{return};encoder.setVertexBuffer(b,offset:0,index:0)}
            encoder.drawPrimitives(type:primitive,vertexStart:0,vertexCount:ptr.count)
        }
    }
    func draw(in view:MTKView) {
        guard wanted,let q=queue,let p=pipeline,let desc=currentRenderPassDescriptor,let drawable=currentDrawable,let cmd=q.makeCommandBuffer(),let enc=cmd.makeRenderCommandEncoder(descriptor:desc) else{return}
        enc.setRenderPipelineState(p)
        let grid=SIMD4<Float>(0.09,0.17,0.19,1)
        var lines:[Vertex]=[];for x in stride(from:CGFloat(20),to:bounds.width,by:20) {lines += [vertex(CGPoint(x:x,y:0),grid),vertex(CGPoint(x:x,y:bounds.height),grid)]}
        for y in stride(from:CGFloat(20),to:bounds.height,by:20) {lines += [vertex(CGPoint(x:0,y:y),grid),vertex(CGPoint(x:bounds.width,y:y),grid)]}
        render(lines,enc,.line)
        for (id,ps) in paths {
            let c=palette[Int(id % Int64(palette.count))]
            render(ps.map{vertex($0,c)},enc)
            if let last=ps.last {
                render([vertex(CGPoint(x:last.x-4,y:last.y),c),vertex(CGPoint(x:last.x+4,y:last.y),c),vertex(CGPoint(x:last.x,y:last.y-4),c),vertex(CGPoint(x:last.x,y:last.y+4),c)],enc,.line)
                if lab?.prediction==true,let pp=future[id],!pp.isEmpty {render(([last]+pp).map{vertex($0,c*0.45)},enc)}
            }
        }
        enc.endEncoding()
        let generation=epoch
        drawable.addPresentedHandler { [weak self] d in
            let t=d.presentedTime
            guard t>0 else{return}
            DispatchQueue.main.async { [weak self] in self?.presented(t,generation) }
        }
        cmd.present(drawable);cmd.commit()
        let now=CACurrentMediaTime()
        if now-lastPublish >= 0.4 {
            lastPublish=now
            if dirty {lab?.stats=tc_stats(engine);dirty=false}
            if now-lastDevice>=2 {lastDevice=now;lab?.deviceInfo()}
            let a=presentation.sorted()
            if a.count>=2, let f=a.first,let l=a.last,l>f,now-l<0.75 {
                lab?.fps=Double(a.count-1)/(l-f)
                let gaps=zip(a.dropFirst(),a).map{($0.0-$0.1)*1000}.sorted()
                lab?.frameP95=gaps[min(gaps.count-1,Int(ceil(Double(gaps.count)*0.95))-1)]
            } else {lab?.fps=0;lab?.frameP95=0}
        }
    }
    private func presented(_ t:Double,_ generation:UInt64) {
        guard wanted,generation==epoch else{return}
        if !presentation.contains(t) {presentation.append(t)}
        let newest=presentation.max() ?? t
        presentation.removeAll{$0<newest-1.5}
        if presentation.count>240 {presentation.removeFirst(presentation.count-240)}
    }
}
struct Trainer:View {
    @State private var start=Date()
    @State private var hits=0
    @State private var count=0
    @State private var gain=1.0
    @State private var cursor:CGPoint?
    private func target(_ size:CGSize,_ date:Date)->CGPoint {
        let t=date.timeIntervalSince(start)
        return CGPoint(x:25+max(0,size.width-50)*(0.5+0.44*sin(t*1.7)),y:25+max(0,size.height-50)*(0.5+0.39*cos(t*1.2)))
    }
    var body:some View {
        VStack(spacing:15) {
            Text("Kéo tâm theo mục tiêu di chuyển rồi nhả tay. Hệ số kéo chỉ áp dụng trong bài tập.").font(.subheadline).foregroundStyle(.secondary)
            HStack {Tile(label:"Trúng",value:"\(hits)/\(count)");Tile(label:"Hệ số kéo",value:String(format:"%.2f×",gain))}
            GeometryReader { geo in
                TimelineView(.animation) { time in
                    let p=target(geo.size,time.date)
                    ZStack {
                        RoundedRectangle(cornerRadius:20).fill(Color.black.opacity(0.5))
                        Circle().strokeBorder(.mint,lineWidth:2).frame(width:44,height:44).position(p)
                        Circle().fill(.white).frame(width:8,height:8).position(cursor ?? CGPoint(x:geo.size.width/2,y:geo.size.height/2))
                    }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged{v in
                        cursor=CGPoint(x:min(geo.size.width,max(0,geo.size.width/2+v.translation.width*gain)),y:min(geo.size.height,max(0,geo.size.height/2+v.translation.height*gain)))
                    }.onEnded{_ in
                        if count<20,let c=cursor {count += 1;let p=target(geo.size,Date());if hypot(c.x-p.x,c.y-p.y)<=22 {hits += 1}}
                        cursor=nil
                    })
                }
            }.frame(minHeight:240)
            Slider(value:$gain,in:0.7...2,step:0.05).disabled(count>0)
            Button("Bắt đầu lại") {hits=0;count=0;start=Date();cursor=nil}.buttonStyle(.borderedProminent)
        }.padding().navigationTitle("Luyện tâm")
    }
}
struct History:View {
    @ObservedObject var lab:Lab
    var body:some View {
        List {
            Section("Kết quả trên thiết bị") {
                if lab.history.isEmpty {Text("Chưa có phiên đo.")}
                ForEach(lab.history) { r in
                    VStack(alignment:.leading,spacing:5) {
                        Text(r.name).font(.headline)
                        Text(r.date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                        Text(String(format:"%.1f Hz • P95 %.1f ms • %.1f FPS",r.hz,r.gap,r.fps)).font(.subheadline)
                        Text(String(format:"%.1f ms callback • %d ngón • %d mẫu",r.delay,r.fingers,r.samples)).font(.caption)
                    }
                }.onDelete{lab.history.remove(atOffsets:$0);lab.persist()}
            }
            Section("Đối chiếu") {Text("Giữ nguyên nhiệt độ, số lần vuốt và độ dài đường vuốt. Đo từ 3 lượt trở lên cho mỗi cấu hình. FPS và touch chỉ phản ánh ứng dụng này.")}
        }.navigationTitle("So sánh")
    }
}
struct Guide:View {
    var body:some View {
        List {
            Section("Tối ưu có cơ sở") {Text("Bật Chế độ trò chơi từ Trung tâm điều khiển khi game hỗ trợ. Tắt nguồn điện thấp nếu cần hiệu năng ổn định. Giữ máy mát, kiểm tra cảm ứng khi không cắm sạc.")}
            Section("Cấu hình đối chứng") {Text("Bản gốc: Thích nghi cảm ứng tắt; thời gian giữ 3,95 giây; vuốt 6×; bỏ qua lặp lại 1,25 giây. Đo trước và sau khi đổi từng mục. Không mặc định các giá trị con có tác dụng khi công tắc chính tắt.")}
            Section("Cài đặt") {Button("Mở cài đặt ứng dụng") {if let u=URL(string:UIApplication.openSettingsURLString){UIApplication.shared.open(u)}};Text("Vào Trợ năng bằng tay. Không có API công khai để tự chỉnh cài đặt cảm ứng toàn hệ thống.")}
            Section("Giới hạn FPS") {Text("iOS không cấp quyền đo FPS hay vẽ HUD tùy ý trên Free Fire từ ứng dụng độc lập. Khi rời màn đo, HUD dừng; không hiển thị số giả.")}
            Section("Quyền riêng tư") {Text("Mọi phép đo lưu cục bộ. Không cần mạng, tài khoản, jailbreak hay quyền đọc ứng dụng khác.")}
        }.navigationTitle("Tối ưu")
    }
}
