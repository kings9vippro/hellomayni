import SwiftUI
import UIKit
import Darwin
import os

struct DeviceTelemetry {
    let memoryMB:Double
    let appFootprintMB:Double?
    let appHeadroomMB:Double
    let activeCores:Int
    let coreCount:Int
    let uptimeHours:Double
    let refreshHz:Int
    let cpuPercent:Double?
    let cpuTime:Double?
    let timestamp:Double
    static func take(previous:DeviceTelemetry?=nil)->DeviceTelemetry {
        let info=ProcessInfo.processInfo
        let now=info.systemUptime
        var vm=task_vm_info_data_t()
        var count=mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size/MemoryLayout<integer_t>.size)
        let result=withUnsafeMutablePointer(to:&vm){ptr in
            ptr.withMemoryRebound(to:integer_t.self,capacity:Int(count)){
                task_info(mach_task_self_,task_flavor_t(TASK_VM_INFO),$0,&count)
            }
        }
        var usage=rusage()
        let cpu:Double?
        if getrusage(RUSAGE_SELF,&usage)==0 {
            cpu=Double(usage.ru_utime.tv_sec)+Double(usage.ru_utime.tv_usec)/1e6+Double(usage.ru_stime.tv_sec)+Double(usage.ru_stime.tv_usec)/1e6
        } else {cpu=nil}
        let percent:Double?
        if let prev=previous,let old=prev.cpuTime,let cpu=cpu,now-prev.timestamp>0.1,cpu>=old {
            percent=(cpu-old)/(now-prev.timestamp)*100
        } else {percent=nil}
        return DeviceTelemetry(memoryMB:Double(info.physicalMemory)/1048576,appFootprintMB:result==KERN_SUCCESS ? Double(vm.phys_footprint)/1048576:nil,appHeadroomMB:Double(os_proc_available_memory())/1048576,activeCores:info.activeProcessorCount,coreCount:info.processorCount,uptimeHours:now/3600,refreshHz:UIScreen.main.maximumFramesPerSecond,cpuPercent:percent,cpuTime:cpu,timestamp:now)
    }
}
struct PrismTelemetryPanel:View {
    @Environment(\.scenePhase) private var phase
    @State private var reading:DeviceTelemetry?
    private let ticker=Timer.publish(every:3,tolerance:0.5,on:.main,in:.common).autoconnect()
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {Text("THIẾT BỊ").font(.caption.bold()).tracking(2).foregroundStyle(.secondary);Spacer();Text("LIVE • 3s").font(.caption2.monospaced()).foregroundStyle(.mint)}
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:9) {
                Tile(label:"RAM vật lý",value:reading.map{String(format:"%.2f GB",$0.memoryMB/1024)} ?? "—")
                Tile(label:"RAM Touch Lab",value:reading?.appFootprintMB.map{String(format:"%.0f MB",$0)} ?? "—")
                Tile(label:"Ngân sách RAM app",value:reading.map{String(format:"%.0f MB",$0.appHeadroomMB)} ?? "—")
                Tile(label:"CPU Touch Lab · %",value:reading?.cpuPercent.map{String(format:"%.1f",$0)} ?? "—")
                Tile(label:"CPU cores",value:reading.map{"\($0.activeCores)/\($0.coreCount)"} ?? "—")
                Tile(label:"Màn hình · tối đa",value:reading.map{"\($0.refreshHz) Hz"} ?? "—")
                Tile(label:"Uptime hệ thống",value:reading.map{String(format:"%.1f h",$0.uptimeHours)} ?? "—")
            }
            Text("CPU/RAM của riêng Touch Lab, không phải Free Fire. 100% CPU tương đương một lõi hoạt động tối đa. Ngân sách RAM không phải RAM trống toàn máy.").font(.caption2).foregroundStyle(.secondary)
        }.onAppear{if phase == .active {reading=DeviceTelemetry.take()}}
         .onChange(of:phase){_,v in if v == .active {reading=DeviceTelemetry.take()}else{reading=nil}}
         .onReceive(ticker){_ in if phase == .active {reading=DeviceTelemetry.take(previous:reading)}}
    }
}
