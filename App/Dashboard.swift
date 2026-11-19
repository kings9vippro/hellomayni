import SwiftUI
import UIKit

struct LabBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            if scheme == .dark {
                Color(red:0.025,green:0.045,blue:0.07)
                RadialGradient(colors:[Color.teal.opacity(0.22),.clear],center:.topLeading,startRadius:0,endRadius:420)
                RadialGradient(colors:[Color.blue.opacity(0.14),.clear],center:.bottomTrailing,startRadius:0,endRadius:340)
            } else {
                Color(red:0.93,green:0.97,blue:0.98)
                RadialGradient(colors:[Color.mint.opacity(0.22),.clear],center:.topLeading,startRadius:0,endRadius:400)
            }
        }.ignoresSafeArea()
    }
}

struct GlassPanel<Content:View>: View {
    @ViewBuilder var content: Content
    var body:some View {
        content.padding(16)
            .frame(maxWidth:.infinity,alignment:.leading)
            .background(.thinMaterial,in:RoundedRectangle(cornerRadius:23))
            .overlay(RoundedRectangle(cornerRadius:23).strokeBorder(.primary.opacity(0.08)))
    }
}

struct Dashboard:View {
    @ObservedObject var lab:Lab
    @ObservedObject var background:BackgroundSettings
    @Binding var selection:Int
    @Binding var appearance:Bool
    @Environment(\.scenePhase) private var phase

    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:15) {
                HStack(alignment:.center) {
                    VStack(alignment:.leading,spacing:5) {
                        Text("Touch Lab").font(.system(size:32,weight:.bold,design:.rounded))
                        Text("Chẩn đoán trên thiết bị  /  5.1.0").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {appearance.toggle()} label:{Image(systemName:appearance ? "sun.max":"moon.stars").font(.title3).frame(width:44,height:44).background(.thinMaterial,in:Circle())}.buttonStyle(.plain).accessibilityLabel("Đổi giao diện")
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment:.center,spacing:14) {
                        ZStack {
                            Circle().strokeBorder(.teal.opacity(0.24),lineWidth:1).frame(width:68,height:68)
                            Circle().fill(.teal.opacity(0.1)).frame(width:54,height:54)
                            Image(systemName:lab.readyForGame ? "checkmark.shield":"waveform.path.ecg").font(.system(size:25,weight:.semibold)).foregroundStyle(.teal)
                        }
                        VStack(alignment:.leading,spacing:5) {
                            Text(lab.readyForGame ? "Đã chuẩn bị phiên chơi":"Kiểm tra hiệu năng").font(.headline)
                            Text(lab.readyForGame ? "Bộ đo đã được yêu cầu dừng.":"Tối ưu tải của Touch Lab và theo dõi tình trạng máy.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength:0)
                    }
                    Divider().padding(.vertical,5)
                    HStack {
                        VStack(alignment:.leading,spacing:4){Text("NHIỆT HỆ THỐNG").font(.caption2.bold()).foregroundStyle(.secondary);Text(lab.thermal).font(.headline)}
                        Spacer()
                        VStack(alignment:.trailing,spacing:4){Text("NGUỒN ĐIỆN THẤP").font(.caption2.bold()).foregroundStyle(.secondary);Text(lab.power ? "Bật":"Tắt").font(.headline)}
                    }
                    FreeFireButton(lab: lab, background: background)
                        .buttonStyle(.borderedProminent)
                        .tint(.mint)
                        .foregroundStyle(.black)
                        .controlSize(.large)
                        .padding(.top, 10)
                    Text("Nếu đã cài Free Fire, chọn Mở trên App Store.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.thinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(LinearGradient(colors: [.teal.opacity(0.23), .blue.opacity(0.08)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(.teal.opacity(0.3), lineWidth: 1)
                }
                Text("DỮ LIỆU ĐO").font(.caption.bold()).tracking(1.5).foregroundStyle(.secondary)
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:9) {
                    Tile(label:"FPS gần nhất · trong app",value:lab.lastFPS>0 ? String(format:"%.1f",lab.lastFPS):"—")
                    Tile(label:"Mẫu cảm ứng · Hz",value:lab.stats.intervals>0 ? String(format:"%.1f",lab.stats.median_hz):"—")
                    Tile(label:"Trễ callback · ms",value:lab.stats.latency_count>0 ? String(format:"%.1f",lab.stats.mean_delivery_ms):"—")
                    Tile(label:"Ngón đồng thời",value:lab.stats.samples>0 ? String(lab.stats.peak_fingers):"—")
                }
                GlassPanel {
                    Text("HUD và bộ đo").font(.headline)
                    Toggle("Tự giảm tải khi nóng",isOn:$lab.adaptive).padding(.top,4)
                    Toggle("Tiết kiệm tải thống kê",isOn:$lab.economy)
                    Toggle("Hiện HUD FPS", isOn: $lab.hudEnabled)
                    Button("Đo FPS và hiện HUD", systemImage: "speedometer") {
                        lab.resumeMeasurement()
                        lab.hudEnabled = true
                        lab.compactMeter = true
                        selection = 0
                    }.buttonStyle(.bordered)
                    Text("HUD hiển thị FPS Metal của Touch Lab và có thể kéo để đổi vị trí.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                GlassPanel {
                    Button {lab.resumeMeasurement();selection=0} label:{entry("Đo cảm ứng & GPU","Thu thập mẫu thật, kiểm tra đa điểm","hand.draw")}
                    Divider()
                    Button {selection=2} label:{entry("Lịch sử đo","So sánh bản gốc và bản tùy chỉnh","chart.line.uptrend.xyaxis")}
                    Divider()
                    Button {selection=3} label:{entry("Cài đặt chuyên sâu","Nhiệt, chế độ nền, hướng dẫn","slider.horizontal.3")}
                }.buttonStyle(.plain)
                if let date=lab.preparationDate {
                    GlassPanel {
                        Text("Phiên chuẩn bị gần nhất").font(.headline)
                        Text(date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                        Text(lab.lastSnapshot).font(.subheadline)
                    }
                }
                Text("Không cần tài khoản • Không gửi dữ liệu lên mạng").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity)
            }.padding(16)
        }.background(LabBackdrop()).toolbar(.hidden,for:.navigationBar)
         .onAppear{lab.deviceInfo();background.reload()}
         .onChange(of:phase){_,v in if v == .active {lab.deviceInfo();background.reload()}}
    }
    func entry(_ title:String,_ subtitle:String,_ icon:String)->some View {
        HStack(spacing:12) {
            Image(systemName:icon).font(.system(size:20)).foregroundStyle(.teal).frame(width:40,height:40).background(.teal.opacity(0.10),in:RoundedRectangle(cornerRadius:12))
            VStack(alignment:.leading,spacing:3){Text(title).font(.subheadline.weight(.semibold));Text(subtitle).font(.caption).foregroundStyle(.secondary)}
            Spacer();Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical,4).contentShape(Rectangle())
    }
}
