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
    @State private var confirmClear=false
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:15) {
                HStack(alignment:.center) {
                    VStack(alignment:.leading,spacing:5) {
                        Text("TOUCH LAB").font(.system(size:12,weight:.heavy,design:.monospaced)).tracking(4).foregroundStyle(.teal)
                        Text("Performance").font(.system(size:32,weight:.bold,design:.rounded))
                        Text("Chẩn đoán trên thiết bị  /  5.0").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {appearance.toggle()} label:{Image(systemName:appearance ? "sun.max":"moon.stars").font(.title3).frame(width:44,height:44).background(.thinMaterial,in:Circle())}.buttonStyle(.plain).accessibilityLabel("Đổi giao diện")
                }
                GlassPanel {
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
                    Button {
                        lab.deviceInfo()
                        if lab.readyForGame {lab.resumeMeasurement();selection=0}
                        else {lab.prepareForGame();if background.enabled {background.setEnabled(false)}}
                    } label: {
                        HStack {Image(systemName:lab.readyForGame ? "play.fill":"bolt.fill");Text(lab.readyForGame ? "Tiếp tục kiểm tra":"Chuẩn bị vào game").fontWeight(.semibold);Spacer();Image(systemName:"arrow.right")}
                        .padding(13).foregroundStyle(.black).background(Color.mint,in:RoundedRectangle(cornerRadius:15))
                    }.buttonStyle(.plain).padding(.top,10)
                }
                Text("DỮ LIỆU ĐO").font(.caption.bold()).tracking(1.5).foregroundStyle(.secondary)
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:9) {
                    Tile(label:"FPS gần nhất · trong app",value:lab.lastFPS>0 ? String(format:"%.1f",lab.lastFPS):"—")
                    Tile(label:"Mẫu cảm ứng · Hz",value:lab.stats.intervals>0 ? String(format:"%.1f",lab.stats.median_hz):"—")
                    Tile(label:"Trễ callback · ms",value:lab.stats.latency_count>0 ? String(format:"%.1f",lab.stats.mean_delivery_ms):"—")
                    Tile(label:"Ngón đồng thời",value:lab.stats.samples>0 ? String(lab.stats.peak_fingers):"—")
                }
                GlassPanel {
                    Text("Tối ưu thông minh").font(.headline)
                    Toggle("Tự giảm tải khi nóng",isOn:$lab.adaptive).padding(.top,4)
                    Toggle("Tiết kiệm tải thống kê",isOn:$lab.economy)
                    Toggle("Khung FPS kéo thả",isOn:$lab.hudEnabled)
                    Button("Mở bộ đo FPS nhỏ") {lab.resumeMeasurement();lab.compactMeter=true;selection=0}.buttonStyle(.bordered)
                    Text("Các chế độ tác động trực tiếp đến bộ đo của Touch Lab, không ép xung hay chỉnh cảm ứng Free Fire.").font(.caption).foregroundStyle(.secondary)
                }
                GlassPanel {
                    Button {lab.resumeMeasurement();selection=0} label:{entry("Đo cảm ứng & GPU","Thu thập mẫu thật, kiểm tra đa điểm","hand.draw")}
                    Divider()
                    Button {selection=1} label:{entry("Luyện kéo tâm","Mục tiêu di chuyển, độ nhạy tùy chỉnh","scope")}
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
