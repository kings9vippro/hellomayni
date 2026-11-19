# Touch Lab Pro 2.0 (TouchOptimizerPro)

iPhone / iOS 18+, arm64. SwiftUI, Metal, UIKit, C++17. No network.

- Genuine UIKit coalesced sample timestamps, per-finger deduplication, approximate callback latency, P95 gap, cancelled gestures and straight-line deviation.
- Metal FPS measured from positive drawable presentedTime timestamps, not fabricated from a display refresh cap. Frame gap P95 and thermal/power state. Pauses when leaving measurement view or app.
- Optional predicted touch visualization; predictions never enter measurements. Independent adjustable moving-target trainer; local history.
- No systemwide touch sensitivity changes, no cross-app FPS overlay, no game memory access. Game Mode and accessibility are manual. Metrics are app-local, not game FPS or physical digitizer benchmark.
- Build via Actions on macOS. Artifact is unsigned, requires valid user signing before stock iOS install. No signing secrets in repository.
- Old README preserved in backup-before-touch-optimizer.

## 3.0
- In-app floating-style status strip with truthful live vs paused/last sample state.
- Bounded two-frame GPU submission, cached grid vertices, small inline vertex chunks, optional adaptive resolution and cadence for thermal pressure; no allocations of separate Metal vertex buffers per line. Optional lower statistics update rate.
- Prepare-to-play releases transient app render state; background snapshot toggle schedules BGAppRefreshTask when iOS permits; stores only device power/thermal status and actual time. No continuous game FPS, systemwide tuning or cross-app overlay.
- Stock iOS only; foreground settings and app-local optimizations. No false boosts. Unsigned IPA requires signing.

## 4.0
New dashboard, glass cards, light/dark appearance, actual measured device metrics and app-local preparation. Cached geometry, bounded completed trails and percentile selection reduce drawing/statistics overhead. Pro retains optional iOS background refresh; Lite uses a different bundle ID and does not register background tasks. Both built for arm64 iPhone iOS 18+ and package-checked in CI. Neither can increase system touch sampling, change Free Fire settings, or render its FPS outside the app. Sign with a valid provisioning profile matching the selected bundle ID, device and certificate. If upgrading an existing install with a different signing team, export needed data and uninstall the old app first, or use the separately provisioned Lite. Unsigned package verification does not verify the user's signature.

## 5.0
Compact draggable FPS-only overlay within app, compact meter, measured GPU command duration, battery and estimated available storage, foreground thermal notifications, immediate deactivation and memory warning handling, thermal hysteresis, constant-memory per-stroke line deviation using running covariance and bounded sample ring, cached percentile queries, extended long-stroke tests. Apple Graphics HUD instructions for compatible developer apps. No cross-app overlay, kernel modification, system digitizer boost or guaranteed gains in another app. Rebuild produces Pro and Lite unsigned packages.

## HUD 6.0 experimental (separate IPA)
ReplayKit broadcast extension counts video sample presentation timestamps only. No pixel/audio processing, recordings or network transmission. AVKit PiP displays a tiny CAP FPS video from that number. It estimates capture cadence, not game render FPS. The OS controls window dimensions, scheduling and background continuation; real device tests required. Both app IDs (com.touchlab.optimizer.hud and com.touchlab.optimizer.hud.broadcast) must be provisioned by the same team for group.com.touchlab.optimizer.hud. Re-signing tools stripping extensions or app group entitlements will not work. No credentials included. Start screen broadcast explicitly, open PiP, then Home/game; stop broadcast in Control Center when finished. The existing Pro/Lite project remains separate and does not request screen broadcast or App Groups.

## HUD 7.0
Reworked live monitor, extension and read/write group checks, explicit errors, retry after audio session activation, small cached PiP image. Native aim trainer uses coalesced UIKit touches, adjustable gain and motion-dependent small-motion damping, and two Core Animation layers. It does not alter other apps' touch handling. Capture can be influenced by PiP itself.

### Signing (macOS)
On Apple Developer register explicit IDs com.touchlab.optimizer.hud and com.touchlab.optimizer.hud.broadcast. Enable App Groups on both, register/assign group.com.touchlab.optimizer.hud, regenerate both development or ad hoc provisioning profiles with the target device and same valid certificate. Import your certificate into a local keychain; never put its private key in the repository. Run security find-identity -v -p codesigning, then:

    bash sign_hud.sh TouchLab-HUD-7.0.0-unsigned.ipa host.mobileprovision extension.mobileprovision CERT_SHA1 TouchLab-HUD-7-signed.ipa

The signing helper verifies exact profile app IDs, team, App Groups authorization, expiration, certificate, device profile class and signatures. It does not generate or bypass Apple authorization. CI builds unsigned because no developer credentials are configured.
