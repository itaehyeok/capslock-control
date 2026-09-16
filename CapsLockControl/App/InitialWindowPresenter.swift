import AppKit
import SwiftUI

/// 앱이 처음 뜰 때 Key Layout 창을 띄울지 결정한다.
///
/// `LSUIElement` 앱에서는 SwiftUI 가 `Window` 씬을 자동으로 만들지 않는다.
/// 그래서 AppDelegate 에서 기존 NSWindow 를 찾아 올리는 방법이 통하지 않고,
/// SwiftUI 의 `openWindow` 액션을 써야 한다. 그 액션은 View 환경에서만 얻을 수
/// 있어서 메뉴바 아이콘 라벨이 뜰 때 한 번 호출한다.
enum InitialWindowPresenter {

    @MainActor private static var hasRun = false

    @MainActor
    static func presentIfNeeded(openWindow: OpenWindowAction) {
        guard !hasRun else { return }
        hasRun = true

        let key = "app.hasCompletedFirstRun"
        let isFirstRun = !UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(true, forKey: key)

        // 평소엔 메뉴바에만 살아 있는다. 다만 아래 경우엔 창을 띄워야
        // 사용자가 무엇을 해야 할지 알 수 있다.
        let shouldShow = isFirstRun
            || !AccessibilityPermission.isTrusted
            || isDebugPickerRequested

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-openSettings") {
            WindowOpener.shared.openSettings()
            return
        }
        #endif

        guard shouldShow else { return }
        WindowOpener.shared.openKeyLayout()
    }

    /// 개발용 `-openPicker` 플래그를 쓰려면 창이 열려 있어야 한다.
    private static var isDebugPickerRequested: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-openPicker")
        #else
        false
        #endif
    }
}
