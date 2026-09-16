import Foundation

/// CapsLock Control 이 전용으로 가져가는 레이어 키.
///
/// 둘 다 HID 레벨에서 남는 펑션 키로 리맵된다.
/// 그래서 event tap 은 모디파이어 플래그를 전혀 건드리지 않아도 된다.
enum LayerKey: String, Codable, CaseIterable, Sendable {
    case capsLock
    case rightOption

    /// 리맵 후 실제로 event tap 에 도착하는 키.
    var triggerKeyCode: KeyCode {
        switch self {
        case .capsLock: .f19
        case .rightOption: .f20
        }
    }

    var displayName: String {
        switch self {
        case .capsLock: "Caps Lock"
        case .rightOption: "Right Option"
        }
    }

    /// UI 에서 "Caps + C" 처럼 보여줄 때 쓰는 짧은 이름.
    var shortName: String {
        switch self {
        case .capsLock: "Caps"
        case .rightOption: "R-Opt"
        }
    }

    static func layer(forTrigger keyCode: KeyCode) -> LayerKey? {
        allCases.first { $0.triggerKeyCode == keyCode }
    }
}
