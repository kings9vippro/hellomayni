import SwiftUI

struct FloatingFPS:View {
    @ObservedObject var lab:Lab
    let active:Bool
    @AppStorage("hud.x.v5") private var x=1.0
    @AppStorage("hud.y.v5") private var y=0.06
    @GestureState private var delta:CGSize = .zero
    var body:some View {
        GeometryReader { geo in
            let w=geo.size.width,h=geo.size.height
            let maxX=max(0,w-92),maxY=max(0,h-64)
            let live=active && lab.measuring && lab.fps>0
            let label=live ? String(format:"%.0f",lab.fps) : "—"
            HStack(spacing:5) {
                Circle().fill(live ? Color.green : Color.gray).frame(width:5,height:5)
                Text(label).font(.system(size:17,weight:.bold,design:.monospaced)).monospacedDigit()
                Text("FPS").font(.system(size:8,weight:.semibold,design:.monospaced))
            }
            .foregroundStyle(.white)
            .frame(width:82,height:32)
            .background(Color.black.opacity(0.86),in:RoundedRectangle(cornerRadius:9))
            .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(Color.white.opacity(0.18),lineWidth:0.5))
            .contentShape(Rectangle())
            .position(x:46+min(maxX,max(0,x*maxX+delta.width)),y:25+min(maxY,max(0,y*maxY+delta.height)))
            .gesture(DragGesture(minimumDistance:2).updating($delta){v,state,_ in state=v.translation}.onEnded{v in
                if maxX>0 {x=min(1,max(0,x+v.translation.width/maxX))}
                if maxY>0 {y=min(1,max(0,y+v.translation.height/maxY))}
            })
            .accessibilityLabel(live ? "FPS Touch Lab: "+label:"FPS Touch Lab: tạm dừng")
            .accessibilityHint("Kéo để đổi vị trí trong ứng dụng")
        }
    }
}
