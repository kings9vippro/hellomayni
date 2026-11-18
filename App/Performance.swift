import SwiftUI
import UIKit
import BackgroundTasks

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey:Any]? = nil) -> Bool {
        BackgroundSettings.register()
        return true
    }
}

struct BackgroundSample: Codable {
    let date: Date
    let thermal: Int
    let lowPower: Bool
    var label:String {
        switch thermal {case 0:return "Bình thường";case 1:return "Ấm";case 2:return "Nóng";case 3:return "Rất nóng";default:return "Không rõ"}
    }
}

final class BackgroundSettings: ObservableObject {
    static let taskID="com.touchlab.optimizer.refresh"
    static let enabledKey="background.health.enabled"
    static let sampleKey="background.health.sample"
    @Published var enabled=false
    @Published var status="Chưa đăng ký"
    @Published var latest:BackgroundSample?
    init(){reload()}
    func reload() {
        enabled=UserDefaults.standard.bool(forKey:Self.enabledKey)
        if let bytes=UserDefaults.standard.data(forKey:Self.sampleKey) {latest=try? JSONDecoder().decode(BackgroundSample.self,from:bytes)}
        if !enabled {status="Đang tắt"}
        else if UIApplication.shared.backgroundRefreshStatus != .available {status="iOS đang hạn chế làm mới nền"}
        else {status="Bật; chờ lịch do iOS quyết định"}
    }
    func setEnabled(_ value:Bool) {
        UserDefaults.standard.set(value,forKey:Self.enabledKey)
        reload()
        if value {scheduleIfEnabled()}
        else {BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:Self.taskID)}
    }
    func scheduleIfEnabled() {
        guard enabled else{return}
        guard UIApplication.shared.backgroundRefreshStatus == .available else {status="iOS đang hạn chế làm mới nền";return}
        do {try Self.submit();status="Đã gửi yêu cầu đến iOS"}
        catch {status="Không đăng ký được: "+error.localizedDescription}
    }
    private static func submit() throws {
        let req=BGAppRefreshTaskRequest(identifier:taskID)
        req.earliestBeginDate=Date(timeIntervalSinceNow:15*60)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:taskID)
        try BGTaskScheduler.shared.submit(req)
    }
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier:taskID,using:nil) { task in
            guard let task=task as? BGAppRefreshTask else {task.setTaskCompleted(success:false);return}
            guard UserDefaults.standard.bool(forKey:enabledKey) else {task.setTaskCompleted(success:true);return}
            // Brief on-device environment snapshot. No timers, polling or FPS estimates.
            let p=ProcessInfo.processInfo
            let sample=BackgroundSample(date:Date(),thermal:p.thermalState.rawValue,lowPower:p.isLowPowerModeEnabled)
            let data=try? JSONEncoder().encode(sample)
            if let data=data {UserDefaults.standard.set(data,forKey:sampleKey)}
            try? submit()
            task.setTaskCompleted(success:data != nil)
        }
    }
}
struct FPSStrip:View {
    @ObservedObject var lab:Lab
    var active:Bool
    var body:some View {
        TimelineView(.periodic(from:.now,by:0.5)) { ctx in
            let live=active && lab.measuring && lab.fps>0 && ctx.date.timeIntervalSince(lab.fpsTime)<1.5
            HStack(spacing:8) {
                Spacer()
                Circle().fill(live ? Color.mint : Color.gray).frame(width:7,height:7)
                Text(live ? String(format:"%.0f FPS  •  LIVE APP",lab.fps) : "FPS • TẠM DỪNG")
                    .font(.system(size:12,weight:.semibold,design:.monospaced))
                if !live && lab.lastFPS>0 {Text(String(format:"(lần cuối %.0f)",lab.lastFPS)).font(.caption2).foregroundStyle(.secondary)}
            }.padding(.horizontal,15).padding(.vertical,5)
              .background(.ultraThinMaterial)
        }.accessibilityLabel("FPS trình chiếu trong ứng dụng Touch Lab")
    }
}
struct PerformanceView:View {
    @ObservedObject var lab:Lab
    @ObservedObject var background:BackgroundSettings
    @Environment(\.scenePhase) private var phase
    var body:some View {
        List {
            Section {
                HStack {Text("Nhiệt hệ thống");Spacer();Text(lab.thermal).foregroundStyle(.mint)}
                HStack {Text("Nguồn điện thấp");Spacer();Text(lab.power ? "Bật":"Tắt").foregroundStyle(.secondary)}
                HStack {Text("Làm mới nền");Spacer();Text(UIApplication.shared.backgroundRefreshStatus == .available ? "Khả dụng":"Bị hạn chế").foregroundStyle(.secondary)}
                Button("Cập nhật trạng thái") {lab.deviceInfo();background.reload()}
            } header:{Text("Trạng thái thiết bị")}
            Section {
                Toggle("Tự giảm tải khi nóng",isOn:$lab.adaptive)
                Toggle("Giảm tải phân tích giao diện",isOn:$lab.economy)
                Toggle("Giữ màn hình sáng trong app",isOn:$lab.keepAwake)
                Toggle("Khung FPS trên các tab",isOn:$lab.hudEnabled)
                Text("Chế độ thích ứng giữ độ phân giải gốc khi máy mát; giảm render còn 85% khi nóng và 75% / tối đa 30 FPS khi rất nóng. Tùy chọn chỉ áp dụng cho bộ đo Touch Lab.").font(.caption).foregroundStyle(.secondary)
            } header:{Text("Tối ưu thực trong ứng dụng")}
            Section {
                Button {
                    lab.prepareForGame()
                } label:{
                    Label(lab.readyForGame ? "Đã yêu cầu dừng bộ đo":"Chuẩn bị vào Free Fire",systemImage:"bolt.circle.fill").font(.headline)
                }
                if lab.readyForGame {
                    Text("Đã yêu cầu dừng GPU của bộ đo, bỏ dữ liệu vẽ tạm và tắt giữ màn hình. Có thể thoát app. Bật lại bộ đo ở tab Cảm ứng.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Tiếp tục đo") {lab.resumeMeasurement()}
                }
                Text("Bật Game Mode từ Trung tâm điều khiển lúc đang chơi game (nếu được hỗ trợ). App này không có quyền ép xung, chỉnh digitizer hoặc dọn RAM của app khác.").font(.caption).foregroundStyle(.secondary)
            } header:{Text("Trước khi chơi")}
            Section {
                Toggle("Kiểm tra trạng thái khi chạy nền",isOn:Binding(get:{background.enabled},set:{background.setEnabled($0)}))
                Text(background.status).font(.caption).foregroundStyle(.secondary)
                if let last=background.latest {
                    Text("Lần kiểm tra nền: "+last.date.formatted(date:.abbreviated,time:.shortened))
                    Text("Nhiệt: "+last.label+" • Tiết kiệm pin: "+(last.lowPower ? "Bật":"Tắt"))
                } else {Text("Chưa nhận mẫu nền.").foregroundStyle(.secondary)}
                Text("iOS quyết định thời điểm thực thi; không chạy liên tục và không đo được FPS Free Fire. Khi chơi game nên tắt nếu muốn tránh tác vụ nền không cần thiết.").font(.caption).foregroundStyle(.secondary)
            } header:{Text("Chạy nền thật • có điều kiện")}
            Section {
                Text("Khung FPS hiển thị khung Metal đã trình chiếu của bộ đo; khi rời bộ đo, chỉ hiển thị trạng thái dừng và mẫu cuối. iOS không cấp quyền vẽ HUD FPS trực tiếp trên Free Fire.")
                Button("Mở cài đặt ứng dụng") {if let u=URL(string:UIApplication.openSettingsURLString){UIApplication.shared.open(u)}}
            } header:{Text("Giới hạn hệ thống")}
        }.navigationTitle("Tối ưu Pro")
         .onAppear{lab.deviceInfo();background.reload()}
         .onChange(of:phase){_,new in if new == .active {lab.deviceInfo();background.reload()}}
    }
}
