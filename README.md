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

## Cài Touch Lab Pro trên iPhone

Các file có tên `-unsigned.ipa` trong GitHub Actions chỉ dùng để kiểm tra bản
build hoặc làm đầu vào cho quy trình ký. iOS cần chữ ký và provisioning profile
hợp lệ để cài lên iPhone.

1. Trên Mac, mở Xcode và thêm Apple ID ở **Xcode → Settings → Accounts**. Tại
   thư mục repo, chạy `brew install xcodegen` rồi `xcodegen generate`.
2. Mở `TouchOptimizerPro.xcodeproj`, chọn target **TouchOptimizerPro** rồi vào
   **Signing & Capabilities**. Bật **Automatically manage signing** và chọn
   **Team** của bạn. Nếu Team không đăng ký được bundle ID mặc định, đặt bundle
   ID riêng, ví dụ `com.tenban.touchlabpro`.
3. Kết nối iPhone chạy iOS 18 trở lên, xác nhận tin cậy máy Mac và bật **Developer
   Mode** nếu iOS yêu cầu. Chọn iPhone trong Xcode rồi nhấn **Run**. Xcode sẽ
   tạo profile phát triển, ký và cài ứng dụng bằng Team đã chọn.

Nếu đang thay thế bản đã ký bằng Team khác, dùng bundle ID riêng để cài song song
và giữ dữ liệu của bản cũ. Nếu cần phân phối IPA cho một iPhone khác, dùng
**Product → Archive → Distribute App** với tài khoản Apple Developer có quyền
phân phối. Với bản Ad Hoc, profile phải chứa UDID của iPhone nhận bản cài.

Nếu iPhone vẫn báo không thể cài, xem thông báo chi tiết trong Xcode khi chạy
trên máy. Với IPA đã ký, đối chiếu Team, bundle ID, hạn profile, danh sách thiết
bị được phép và phiên bản iOS tối thiểu của chính bản IPA đó.
