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

        if model.conflictingApps.contains(where: \.isIntercepting) {
            Button("충돌 해결 방법 보기...") { WindowOpener.shared.openKeyLayout() }
        }

        Button("Open Key Layout...") { WindowOpener.shared.openKeyLayout() }

        // 동기화는 고급 기능이다. 저장소를 넣은 사람에게만 메뉴에 보인다.
        if model.sync.isConfigured {
            Text(model.sync.statusLine(for: model.config))
            Button("Export to GitHub") { Task { await model.sync.export() } }
                .disabled(model.sync.isWorking)
            Button("Import from GitHub...") { model.sync.requestImportSheet() }
                .disabled(model.sync.isWorking)
        }

        Button("Settings...") { WindowOpener.shared.openSettings() }
            .keyboardShortcut(",")

        Divider()
        Button("Quit CapsLock Control") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        guard model.isTrusted else { return "권한 필요" }
        guard model.isEngineRunning else { return "정지됨" }
        // 엔진이 멀쩡히 돌아도 다른 도구가 키를 먼저 채가면 아무것도 안 먹는다.
        // "동작 중" 만 보여 주면 사용자는 원인을 찾을 길이 없다.
        if let blocker = model.conflictingApps.first(where: \.isIntercepting) {
            return "⚠︎ \(blocker.name) 충돌 · 단축키가 안 먹을 수 있음"
        }
        return "동작 중 · 단축키 \(model.bindingCount)개"
    }


}

enum WindowIdentifier {
    static let keyLayout = "capslockcontrol-main"
    /// SwiftUI 의 `Settings` 씬은 메뉴바 전용 앱에서 열기가 불안정해서
    /// 평범한 Window 로 만든다. 메뉴에서 ⌘, 로 연다.
    static let settings = "capslockcontrol-settings"
}
