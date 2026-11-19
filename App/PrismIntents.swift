import AppIntents
import Foundation

struct OpenPrismFPS: AppIntent {
    static var title: LocalizedStringResource = "Mở FPS nổi"
    static var description=IntentDescription("Mở bảng đo FPS và điều khiển PiP của Touch Lab.")
    static var openAppWhenRun=true
    @MainActor func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("fps|"+UUID().uuidString,forKey:"prism.shortcut.request")
        return .result()
    }
}
struct PreparePrismGame: AppIntent {
    static var title: LocalizedStringResource = "Chuẩn bị phiên chơi"
    static var description=IntentDescription("Giảm công việc đo và vẽ của Touch Lab trước khi chơi.")
    static var openAppWhenRun=true
    @MainActor func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("prepare|"+UUID().uuidString,forKey:"prism.shortcut.request")
        return .result()
    }
}
struct PrismShortcuts: AppShortcutsProvider {
    static var appShortcuts:[AppShortcut] {
        AppShortcut(intent:OpenPrismFPS(),phrases:["Open FPS in \(.applicationName)"],shortTitle:"Mở FPS nổi",systemImageName:"pip.enter")
        AppShortcut(intent:PreparePrismGame(),phrases:["Prepare gaming with \(.applicationName)"],shortTitle:"Chuẩn bị phiên chơi",systemImageName:"bolt.fill")
    }
}
