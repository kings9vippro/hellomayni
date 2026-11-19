import SwiftUI
import UIKit

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
                    Text("Phím tắt trước khi chơi").font(.headline)
                    Text("Tạo một Phím tắt trên iPhone có tên dưới đây. Thêm các tác vụ hệ thống theo thứ tự:").font(.subheadline)
                    Text("1. Đặt Chế độ nguồn điện thấp → Tắt\n2. Đặt Tập trung → Chơi trò chơi (nếu đã tạo)\n3. Mở ứng dụng → Free Fire VN").font(.subheadline)
                    TextField("Tên phím tắt",text:$name).textFieldStyle(.roundedBorder)
                    Button("Mở Phím tắt để thiết lập"){open(URL(string:"shortcuts://create-shortcut")!)}.buttonStyle(.bordered)
                    Button {
                        lab.prepareForGame()
                        var c=URLComponents();c.scheme="shortcuts";c.host="run-shortcut";c.queryItems=[URLQueryItem(name:"name",value:name.trimmingCharacters(in:.whitespacesAndNewlines))]
                        if let url=c.url {open(url)}
                    } label:{Label("Chạy phím tắt đã tạo",systemImage:"play.fill").frame(maxWidth:.infinity).padding(7)}.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Text("Chính Phím tắt mới thực thi các tác vụ hệ thống đã được bạn cho phép. Touch Lab không tự tạo hay chỉnh trợ năng bằng quyền riêng.").font(.caption).foregroundStyle(.secondary)
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
