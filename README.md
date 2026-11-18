# Touch Lab Pro 2.0 (TouchOptimizerPro)

iPhone / iOS 18+, arm64. SwiftUI, Metal, UIKit, C++17. No network.

- Genuine UIKit coalesced sample timestamps, per-finger deduplication, approximate callback latency, P95 gap, cancelled gestures and straight-line deviation.
- Metal FPS measured from positive drawable presentedTime timestamps, not fabricated from a display refresh cap. Frame gap P95 and thermal/power state. Pauses when leaving measurement view or app.
- Optional predicted touch visualization; predictions never enter measurements. Independent adjustable moving-target trainer; local history.
- No systemwide touch sensitivity changes, no cross-app FPS overlay, no game memory access. Game Mode and accessibility are manual. Metrics are app-local, not game FPS or physical digitizer benchmark.
- Build via Actions on macOS. Artifact is unsigned, requires valid user signing before stock iOS install. No signing secrets in repository.
- Old README preserved in backup-before-touch-optimizer.
