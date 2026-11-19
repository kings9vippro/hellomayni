import ReplayKit
import CoreMedia
import Foundation
final class SampleHandler: RPBroadcastSampleHandler {
    private var rate=CaptureRate()
    private var lastPublish:Double=0
    private let lock=NSLock()
    private var running=false
    override func broadcastStarted(withSetupInfo setupInfo:[String:NSObject]?) {
        lock.lock();defer{lock.unlock()}
        guard ScreenMetrics.url != nil else {
            finishBroadcastWithError(NSError(domain:"TouchLabHUD",code:1,userInfo:[NSLocalizedDescriptionKey:"Missing authorized App Group provisioning."]))
            return
        }
        running=true;rate.reset();lastPublish=0;publish("waiting",nil)
    }
    override func broadcastPaused(){lock.lock();defer{lock.unlock()};running=false;rate.reset();publish("paused",nil)}
    override func broadcastResumed(){lock.lock();defer{lock.unlock()};running=true;rate.reset();lastPublish=0;publish("waiting",nil)}
    override func broadcastFinished(){lock.lock();defer{lock.unlock()};running=false;rate.reset();publish("ended",nil)}
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else{return}
        lock.lock();defer{lock.unlock()}
        guard running else{return}
        // Consume timestamps only. Never read pixels, encode, store or transmit video/audio.
        rate.record(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)))
        let now=ProcessInfo.processInfo.systemUptime
        if now-lastPublish>=0.5 {lastPublish=now;publish("live",rate.fps)}
    }
    private func publish(_ state:String,_ fps:Double?) {
        ScreenMetrics.write(ScreenSample(uptime:ProcessInfo.processInfo.systemUptime,fps:fps,state:state))
    }
}
