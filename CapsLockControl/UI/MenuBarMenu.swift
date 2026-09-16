import SwiftUI

/// 메뉴바 아이콘을 클릭하면 나오는 메뉴.
struct MenuBarMenu: View {
    let model: EngineModel

    var body: some View {
        Text(statusLine)
        Divider()

        Toggle("Enabled", isOn: Binding(
            get: { model.isEngineRunning },
            set: { _ in model.toggle() }
        ))
        .disabled(!model.isTrusted && !model.isEngineRunning)

        if !model.isTrusted {
            Button("손쉬운 사용 권한 열기...") { model.requestAccessibilityPermission() }
        }

        Divider()

        Button("Open Key Layout...") { WindowOpener.shared.openKeyLayout() }

        Text(model.sync.statusLine(for: model.config))
        Button("Export to GitHub") { Task { await model.sync.export() } }
            .disabled(!model.sync.isConfigured || model.sync.isWorking)
        Button("Import from GitHub...") { model.sync.requestImportSheet() }
            .disabled(!model.sync.isConfigured || model.sync.isWorking)

        Button("Settings...") { WindowOpener.shared.openSettings() }
            .keyboardShortcut(",")

        Divider()
        Button("Quit CapsLock Control") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        guard model.isTrusted else { return "권한 필요" }
        guard model.isEngineRunning else { return "정지됨" }
        return "동작 중 · 단축키 \(model.bindingCount)개"
    }


}

enum WindowIdentifier {
    static let keyLayout = "capslockcontrol-main"
    /// SwiftUI 의 `Settings` 씬은 메뉴바 전용 앱에서 열기가 불안정해서
    /// 평범한 Window 로 만든다. 메뉴에서 ⌘, 로 연다.
    static let settings = "capslockcontrol-settings"
}
