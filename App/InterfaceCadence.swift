import SwiftUI
import QuartzCore
import UIKit

// Actual callback cadence of this app, not GPU FPS of other apps.
final class InterfaceCadence: NSObject, ObservableObject {
    static let shared=InterfaceCadence()
    @Published private(set) var hz:Double?
    @Published private(set) var p95:Double?
    private var link:CADisplayLink?
    private var rate=CaptureRate()
    private var lastPublish=0.0
    func setActive(_ active:Bool) {
        if !active {
            link?.invalidate();link=nil;rate.reset();lastPublish=0
            if hz != nil {hz=nil};if p95 != nil {p95=nil}
            return
        }
        guard link == nil else{return}
        let next=CADisplayLink(target:self,selector:#selector(tick(_:)))
        next.add(to:.main,forMode:.common);link=next
    }
    @objc private func tick(_ sender:CADisplayLink) {
        rate.record(sender.timestamp)
        if sender.timestamp-lastPublish>=0.75 {
            lastPublish=sender.timestamp
            let next=rate.fps.map{($0*10).rounded()/10}, tail=rate.p95MS.map{($0*10).rounded()/10}
            if hz != next {hz=next}
            if p95 != tail {p95=tail}
        }
    }
}
struct PulsePrimary:ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduced
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.subheadline.weight(.semibold)).frame(maxWidth:.infinity).padding(.vertical,15)
            .foregroundStyle(.black)
            .background(LinearGradient(colors:[.cyan,.mint],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:17))
            .opacity(configuration.isPressed ? 0.78:1)
            .scaleEffect(configuration.isPressed && !reduced ? 0.97:1)
            .animation(reduced ? nil:.spring(response:0.26,dampingFraction:0.76),value:configuration.isPressed)
    }
}
