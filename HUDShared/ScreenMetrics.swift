import Foundation
struct ScreenSample: Codable {
    let uptime: Double
    let fps: Double?
    let state: String
}
enum ScreenMetrics {
    static let group = "group.com.touchlab.optimizer.hud"
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:group)?.appendingPathComponent("capture-fps.json")
    }
    static func write(_ sample: ScreenSample) {
        guard let url=url,let data=try? JSONEncoder().encode(sample) else{return}
        try? data.write(to:url,options:.atomic)
    }
    static func read() -> ScreenSample? {
        guard let url=url,let data=try? Data(contentsOf:url),let s=try? JSONDecoder().decode(ScreenSample.self,from:data) else{return nil}
        let age=ProcessInfo.processInfo.systemUptime-s.uptime
        return age>=0 && age<2.5 ? s:nil
    }
}
struct CaptureRate {
    private var stamps:[Double]=[]
    mutating func reset(){stamps.removeAll(keepingCapacity:true)}
    mutating func record(_ t:Double) {
        guard t.isFinite else{return}
        if let last=stamps.last {
            if t==last{return}
            if t<last || t-last>2 {reset()}
        }
        stamps.append(t)
        if let first=stamps.firstIndex(where:{$0>=t-1.25}),first>0 {stamps.removeFirst(first)}
        if stamps.count>256 {stamps.removeFirst(stamps.count-256)}
    }
    var fps:Double? {
        guard stamps.count>=3,let first=stamps.first,let last=stamps.last,last-first>=0.24 else{return nil}
        return Double(stamps.count-1)/(last-first)
    }
}
