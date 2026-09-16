import AppKit
import SwiftUI

/// Key Layout 창을 여는 통로.
///
/// `LSUIElement` 앱에서는 SwiftUI 가 창을 자동으로 만들지 않고, 창을 여는
/// `openWindow` 액션은 View 환경에서만 얻을 수 있다. 그래서 메뉴바 라벨이
/// 뜰 때 액션을 여기 등록해 두고, AppDelegate 같은 AppKit 쪽에서도 꺼내 쓴다.
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()

    private var openWindowAction: OpenWindowAction?

    private init() {}

    func register(_ action: OpenWindowAction) {
        openWindowAction = action
    }

    func openKeyLayout() {
        open(WindowIdentifier.keyLayout)
    }

    func openSettings() {
        open(WindowIdentifier.settings)
    }

    private func open(_ id: String) {
        openWindowAction?(id: id)
        NSApp.activate()
    }
}
