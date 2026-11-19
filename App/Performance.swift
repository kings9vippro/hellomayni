import SwiftUI
import UIKit
import BackgroundTasks

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey:Any]? = nil) -> Bool {
        #if !TOUCHLAB_LITE
        BackgroundSettings.register()
        #endif
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
    static var supportsRefresh:Bool {
        #if TOUCHLAB_LITE
        return false
        #else
        return true
        #endif
    }
    static let enabledKey="background.health.enabled"
    static let sampleKey="background.health.sample"
    private var pausedForGame = false
    @Published var enabled=false
    @Published var status="Chưa đăng ký"
    @Published var latest:BackgroundSample?
    init(){reload()}
    func reload() {
        guard Self.supportsRefresh else {enabled=false;status="Bản Lite không đăng ký tác vụ nền";return}
        enabled=UserDefaults.standard.bool(forKey:Self.enabledKey)
        if let bytes=UserDefaults.standard.data(forKey:Self.sampleKey) {latest=try? JSONDecoder().decode(BackgroundSample.self,from:bytes)}
        if !enabled {status="Đang tắt"}
        else if pausedForGame { status = "Tạm dừng làm mới nền cho phiên chơi" }
        else if UIApplication.shared.backgroundRefreshStatus != .available {status="iOS đang hạn chế làm mới nền"}
        else {status="Bật; chờ lịch do iOS quyết định"}
    }
    func setEnabled(_ value:Bool) {
        guard Self.supportsRefresh else{return}
        UserDefaults.standard.set(value,forKey:Self.enabledKey)
        reload()
        if value {scheduleIfEnabled()}
        else {BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:Self.taskID)}
    }
    func pauseForGame() {
        guard Self.supportsRefresh else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskID)
        pausedForGame = true
        reload()
    }
    func resumeAfterGame() {
        guard pausedForGame else { return }
        pausedForGame = false
        reload()
        scheduleIfEnabled()
    }
    func scheduleIfEnabled() {
        guard Self.supportsRefresh, enabled, !pausedForGame else { return }
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
struct FreeFireButton: View {
    @ObservedObject var lab: Lab
    @ObservedObject var background: BackgroundSettings
    @Environment(\.openURL) private var openURL
    @State private var failed = false

    private let storeURL = URL(string: "https://apps.apple.com/vn/app/free-fire-vn/id6788307486?l=vi")!

    var body: some View {
        Button {
            lab.prepareForGame()
            background.pauseForGame()
            openURL(storeURL) { accepted in
                if !accepted { failed = true }
            }
        } label: {
            Label("Free Fire VN trên App Store", systemImage: "gamecontroller.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Không mở được App Store", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
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
                HStack {Text("Pin hiện tại");Spacer();Text(lab.battery.map{"\($0)%"} ?? "—")}
                HStack {Text("Dung lượng khả dụng ước tính");Spacer();Text(lab.storageGB.map{String(format:"%.1f GB",$0)} ?? "—")}
                HStack {Text("Làm mới nền");Spacer();Text(UIApplication.shared.backgroundRefreshStatus == .available ? "Khả dụng":"Bị hạn chế").foregroundStyle(.secondary)}
                Button("Cập nhật trạng thái") {lab.deviceInfo();lab.refreshStorage();background.reload()}
            } header:{Text("Trạng thái thiết bị")}
            Section {
                Toggle("Tự giảm tải khi nóng",isOn:$lab.adaptive)
                Toggle("Giảm tải phân tích giao diện",isOn:$lab.economy)
                Toggle("Giữ màn hình sáng trong app",isOn:$lab.keepAwake)
                Toggle("Khung FPS trên các tab",isOn:$lab.hudEnabled)
                Text("Chế độ thích ứng giảm tải theo nhiệt độ, ưu tiên giữ nhịp khung hình và chỉ phục hồi độ phân giải sau khoảng ổn định. Chỉ áp dụng cho Touch Lab.").font(.caption).foregroundStyle(.secondary)
            } header:{Text("Tối ưu thực trong ứng dụng")}
            Section {
                FreeFireButton(lab: lab, background: background)
                if lab.readyForGame {
                    Text("Đã yêu cầu dừng GPU của bộ đo, bỏ dữ liệu vẽ tạm và tắt giữ màn hình. Có thể thoát app. Bật lại bộ đo ở tab Cảm ứng.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Tiếp tục đo") {lab.resumeMeasurement()}
                }
                Text("Bật Game Mode từ Trung tâm điều khiển lúc đang chơi game (nếu được hỗ trợ). App này không có quyền ép xung, chỉnh digitizer hoặc dọn RAM của app khác.").font(.caption).foregroundStyle(.secondary)
            } header:{Text("Trước khi chơi")}
            Section("Độ nhạy trong Free Fire") {
                Text("Trong cài đặt Độ nhạy của game, ghi lại cấu hình hiện tại. Nếu tâm kéo nặng, tăng nhẹ mục Tổng quan rồi thử cùng một động tác trong sân tập. Chỉnh riêng từng loại ống ngắm và giảm lại nếu tâm vượt mục tiêu.")
                Text("Tab Đo cảm ứng kiểm tra tần suất mẫu, khoảng mẫu P95 và độ trễ callback trên iPhone. Cài đặt độ nhạy áp dụng từ chính Free Fire.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Kiểm tra trạng thái khi chạy nền",isOn:Binding(get:{background.enabled},set:{background.setEnabled($0)})).disabled(!BackgroundSettings.supportsRefresh)
                Text(background.status).font(.caption).foregroundStyle(.secondary)
                if let last=background.latest {
                    Text("Lần kiểm tra nền: "+last.date.formatted(date:.abbreviated,time:.shortened))
                    Text("Nhiệt: "+last.label+" • Tiết kiệm pin: "+(last.lowPower ? "Bật":"Tắt"))
                } else {Text("Chưa nhận mẫu nền.").foregroundStyle(.secondary)}
                Text("iOS quyết định thời điểm thực thi; không chạy liên tục và không đo được FPS Free Fire. Khi chơi game nên tắt nếu muốn tránh tác vụ nền không cần thiết.").font(.caption).foregroundStyle(.secondary)
            } header:{Text("Chạy nền thật • có điều kiện")}
            Section {
                Text("Kéo ô FPS nhỏ tới vị trí bạn muốn trong Touch Lab. Khi dừng bộ đo, ô hiện dấu gạch, không giả lập FPS. iOS không cho ứng dụng này phủ lên Free Fire.")
                Text("Graphics HUD của Apple: Cài đặt → Nhà phát triển → Graphics HUD → Show Graphics HUD (nếu có). Tính năng này chỉ hiện ở ứng dụng phát triển tương thích; không đảm bảo hoạt động với Free Fire bản App Store.").font(.caption).foregroundStyle(.secondary)
                Link("Hướng dẫn Metal HUD của Apple",destination:URL(string:"https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance")!)
                Button("Mở cài đặt ứng dụng") {if let u=URL(string:UIApplication.openSettingsURLString){UIApplication.shared.open(u)}}
            } header:{Text("Giới hạn hệ thống")}
        }.navigationTitle("Tối ưu Pro")
         .onAppear{lab.deviceInfo();background.reload()}
         .onChange(of:phase){_,new in if new == .active {lab.deviceInfo();background.reload()}}
    }
}
