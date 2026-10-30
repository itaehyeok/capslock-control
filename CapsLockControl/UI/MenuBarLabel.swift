import AppKit
import SwiftUI

/// 메뉴바에 보이는 아이콘. 상태에 따라 모양이 바뀐다.
///
/// 첫 실행 때 창을 띄우는 일도 여기서 한다. `openWindow` 액션은 View 환경에서만
/// 얻을 수 있고, 메뉴바 라벨은 앱이 뜨는 순간 그려지는 유일한 View 라서다.
struct MenuBarLabel: View {
    let model: EngineModel

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: MenuBarIcon.image(for: state))
            .task {
                WindowOpener.shared.register(openWindow)
                InitialWindowPresenter.presentIfNeeded(openWindow: openWindow)
            }
    }

    private var state: MenuBarIcon.State {
        MenuBarIcon.State(
            isTrusted: model.isTrusted,
            isEngineRunning: model.isEngineRunning,
            hasUpdate: model.updates.available != nil
        )
    }
}

/// 메뉴바 아이콘 그림. 모두 template 이라 다른 메뉴바 아이콘처럼 메뉴바 밝기에 맞춰
/// 검정·흰색으로 바뀐다.
///
/// - 권한이 없으면 오른쪽 아래에 느낌표 배지. SF Symbols 에는
///   `keyboard.badge.exclamationmark` 가 없어서(이름을 쓰면 빈 칸이 된다) 직접 그린다.
///   배치는 `keyboard.badge.ellipsis` 를 따랐다.
/// - 새 버전이 있으면 오른쪽 위에 점. 창을 잘 열지 않는 앱이라 메뉴를 열어 보지 않아도
///   새 버전이 있는 걸 알 수 있게 한다.
@MainActor
private enum MenuBarIcon {
    struct State: Hashable {
        var isTrusted: Bool
        var isEngineRunning: Bool
        var hasUpdate: Bool
    }

    /// 상태가 몇 가지뿐이라 한 번 그린 건 다시 쓴다.
    private static var cache: [State: NSImage] = [:]

    static func image(for state: State) -> NSImage {
        if let image = cache[state] { return image }
        let image = draw(state)
        cache[state] = image
        return image
    }

    private static func draw(_ state: State) -> NSImage {
        let symbol = state.isTrusted && state.isEngineRunning ? "keyboard.fill" : "keyboard"
        let keyboard = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()
        let showsWarning = !state.isTrusted
        guard showsWarning || state.hasUpdate else { return keyboard }

        let badge = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 8, weight: .bold)) ?? NSImage()
        let size = NSSize(width: keyboard.size.width + 3, height: keyboard.size.height + (showsWarning ? 2 : 0))

        let image = NSImage(size: size, flipped: false) { rect in
            let keyboardRect = NSRect(
                x: 0, y: rect.height - keyboard.size.height,
                width: keyboard.size.width, height: keyboard.size.height
            )
            keyboard.draw(in: keyboardRect)
            if showsWarning {
                let badgeRect = NSRect(
                    x: rect.width - badge.size.width, y: 0,
                    width: badge.size.width, height: badge.size.height
                )
                clearAround(badgeRect)
                badge.draw(in: badgeRect)
            }
            if state.hasUpdate {
                // 키보드 몸통의 오른쪽 위 모서리에 걸친다. 몸통 위 끝은 그림 위에서 2.5pt 아래다.
                let diameter: CGFloat = 5.5
                let dotRect = NSRect(
                    x: keyboardRect.maxX - diameter / 2 - 0.5,
                    y: keyboardRect.maxY - 2.5 - diameter / 2 - 0.5,
                    width: diameter, height: diameter
                )
                clearAround(dotRect)
                NSColor.black.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = [
            showsWarning ? "손쉬운 사용 권한 필요" : nil,
            state.hasUpdate ? "새 버전 있음" : nil,
        ].compactMap { $0 }.joined(separator: ", ")
        return image
    }

    /// 배지 둘레의 키보드 선을 지워 배지가 떨어져 보이게 한다.
    nonisolated private static func clearAround(_ rect: NSRect) {
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: rect.insetBy(dx: -1.5, dy: -1.5)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }
}
