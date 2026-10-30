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
        icon
            .task {
                WindowOpener.shared.register(openWindow)
                InitialWindowPresenter.presentIfNeeded(openWindow: openWindow)
            }
    }

    private var icon: Image {
        if !model.isTrusted { return Image(nsImage: Self.permissionNeededImage) }
        return Image(systemName: model.isEngineRunning ? "keyboard.fill" : "keyboard")
    }

    /// 손쉬운 사용 권한이 없을 때 아이콘. 키보드 오른쪽 아래에 느낌표 배지를 얹는다.
    ///
    /// SF Symbols 에는 `keyboard.badge.exclamationmark` 가 없어서(이름을 쓰면 빈 칸이
    /// 된다) 직접 그린다. 배치는 `keyboard.badge.ellipsis` 를 따랐다. template 이라
    /// 다른 메뉴바 아이콘처럼 메뉴바 밝기에 맞춰 검정·흰색으로 바뀐다.
    private static let permissionNeededImage: NSImage = {
        let keyboard = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil) ?? NSImage()
        let badge = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 8, weight: .bold)) ?? NSImage()
        let size = NSSize(width: keyboard.size.width + 3, height: keyboard.size.height + 2)

        let image = NSImage(size: size, flipped: false) { rect in
            keyboard.draw(in: NSRect(
                x: 0, y: rect.height - keyboard.size.height,
                width: keyboard.size.width, height: keyboard.size.height
            ))
            let badgeRect = NSRect(
                x: rect.width - badge.size.width, y: 0,
                width: badge.size.width, height: badge.size.height
            )
            // 배지 둘레의 키보드 선을 지워 배지가 떨어져 보이게 한다.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            badge.draw(in: badgeRect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "손쉬운 사용 권한 필요"
        return image
    }()
}
