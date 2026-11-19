import Foundation
struct ScreenSample: Codable {
    let uptime: Double
    let fps: Double?
    let state: String
    var p95MS: Double? = nil
    var count: Int? = nil
}
enum ScreenMetrics {
    static let group = "group.com.touchlab.optimizer.hud"
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:group)?.appendingPathComponent("capture-fps.json")
    }
    static func probe() -> Bool {
        guard let base=url?.deletingLastPathComponent() else{return false}
        let file=base.appendingPathComponent("probe-"+UUID().uuidString)
        do {let bytes=Data([0x54,0x4c]);try bytes.write(to:file,options:.atomic);defer{try? FileManager.default.removeItem(at:file)};return try Data(contentsOf:file)==bytes}
        catch{return false}
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
    var count:Int {stamps.count}
    var p95MS:Double? {
        guard stamps.count>=3 else{return nil}
        let gaps=zip(stamps.dropFirst(),stamps).map{($0.0-$0.1)*1000}.sorted()
        guard !gaps.isEmpty else{return nil}
        return gaps[max(0,Int(ceil(Double(gaps.count)*0.95))-1)]
    }
    var fps:Double? {
        guard stamps.count>=3,let first=stamps.first,let last=stamps.last,last-first>=0.24 else{return nil}
        return Double(stamps.count-1)/(last-first)
    }
}
