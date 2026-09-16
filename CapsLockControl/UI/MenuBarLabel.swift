import SwiftUI

/// 메뉴바에 보이는 아이콘. 상태에 따라 모양이 바뀐다.
///
/// 첫 실행 때 창을 띄우는 일도 여기서 한다. `openWindow` 액션은 View 환경에서만
/// 얻을 수 있고, 메뉴바 라벨은 앱이 뜨는 순간 그려지는 유일한 View 라서다.
struct MenuBarLabel: View {
    let model: EngineModel

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: symbol)
            .task {
                WindowOpener.shared.register(openWindow)
                InitialWindowPresenter.presentIfNeeded(openWindow: openWindow)
            }
    }

    private var symbol: String {
        if !model.isTrusted { return "keyboard.badge.exclamationmark" }
        return model.isEngineRunning ? "keyboard.fill" : "keyboard"
    }
}
