import SwiftUI
import UIKit
import AppIntents

struct SystemSetupView:View {
    @ObservedObject var lab:Lab
    @Environment(\.scenePhase) private var phase
    @AppStorage("game.shortcut.name") private var name="Touch Lab Game"
    @State private var voiceOver=false
    @State private var switchControl=false
    @State private var assistiveTouch=false
    @State private var motion=false
    @State private var message=""
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:15) {
                Text("SYSTEM • iOS").font(.caption.bold()).tracking(3).foregroundStyle(.mint)
                Text("Thiết lập thiết bị").font(.largeTitle.bold())
                GlassPanel {
                    Text("Trạng thái đo từ iOS").font(.headline)
                    row("Nguồn điện thấp",lab.power ? "Bật":"Tắt")
                    row("Nhiệt hệ thống",lab.thermal)
                    row("VoiceOver",voiceOver ? "Bật":"Tắt")
                    row("Điều khiển công tắc",switchControl ? "Bật":"Tắt")
                    row("AssistiveTouch",assistiveTouch ? "Bật":"Tắt")
                    row("Giảm chuyển động",motion ? "Bật":"Tắt")
                    Button("Kiểm tra lại"){refresh()}.buttonStyle(.bordered)
                }
                GlassPanel {
                    Text("Phím tắt có sẵn").font(.headline)
                    Text("Hai App Shortcuts được đăng ký cùng Touch Lab. Không cần tự nhập từng tác vụ.").font(.subheadline).foregroundStyle(.secondary)
                    Label("Mở FPS nổi",systemImage:"pip.enter").font(.subheadline)
                    Label("Chuẩn bị phiên chơi",systemImage:"bolt.fill").font(.subheadline)
                    Button("Cài đặt phím tắt") {
                        PrismShortcuts.updateAppShortcutParameters()
                        open(URL(string:"shortcuts://")!)
                    }.buttonStyle(.borderedProminent)
                    ShortcutsLink()
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Text("App Shortcuts chỉ thực hiện tác vụ của ứng dụng. Để đổi Nguồn điện thấp, Tập trung hoặc mở game, hãy thêm tác vụ hệ thống trong Phím tắt nếu cần.").font(.caption).foregroundStyle(.secondary)
                }
                GlassPanel {
                    Text("Ưu tiên trước khi vào rank").font(.headline)
                    Text("Bật Chế độ trò chơi khi game hỗ trợ; giữ máy mát; kiểm tra Thích nghi cảm ứng bằng tay; giữ mạng ổn định. Không chạy capture khi cần hiệu năng tối đa.").font(.subheadline)
                    Text("Không có API công khai để ép xung cảm ứng, tăng Hz digitizer hoặc sửa RAM/CPU của ứng dụng khác.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(16)
        }.background(LabBackdrop()).navigationTitle("Hệ thống").navigationBarTitleDisplayMode(.inline)
        .onAppear{refresh()}.onChange(of:phase){_,v in if v == .active {refresh()}}
    }
    func refresh(){
        lab.deviceInfo()
        voiceOver=UIAccessibility.isVoiceOverRunning
        switchControl=UIAccessibility.isSwitchControlRunning
        assistiveTouch=UIAccessibility.isAssistiveTouchRunning
        motion=UIAccessibility.isReduceMotionEnabled
    }
    func row(_ title:String,_ value:String)->some View {HStack{Text(title).font(.subheadline);Spacer();Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)}}
    func open(_ url:URL){UIApplication.shared.open(url,options:[:]){ok in DispatchQueue.main.async{message=ok ? "Đã gửi yêu cầu mở Phím tắt. Xác nhận trong iOS nếu được hỏi.":"Không mở được Phím tắt."}}}
}
