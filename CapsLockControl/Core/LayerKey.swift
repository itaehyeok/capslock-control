import Foundation

/// CapsLock Control 이 전용으로 가져가는 레이어 키.
///
/// HID 레벨에서 남는 펑션 키로 리맵된다.
/// 그래서 event tap 은 모디파이어 플래그를 전혀 건드리지 않아도 된다.
///
/// 지금은 Caps Lock 하나뿐이다. 예전에는 Right Option 도 두 번째 레이어였는데,
/// 남들이 쓰기엔 오른쪽 ⌥ 를 빼앗는 게 더 손해라 뺐다. 설정 파일의
/// `layers` 를 레이어 이름으로 나눠 두는 형식은 그대로 둔다.
enum LayerKey: String, Codable, CaseIterable, Sendable {
    case capsLock

    /// 예전 설정 파일에 남아 있을 수 있는 레이어 이름. 읽을 때 조용히 건너뛴다.
    static let retiredRawValues: Set<String> = ["rightOption"]

    /// 리맵 후 실제로 event tap 에 도착하는 키.
    var triggerKeyCode: KeyCode {
        switch self {
        case .capsLock: .f19
        }
    }

    var displayName: String {
        switch self {
        case .capsLock: "Caps Lock"
        }
    }

    /// UI 에서 "Caps + C" 처럼 보여줄 때 쓰는 짧은 이름.
    var shortName: String {
        switch self {
        case .capsLock: "Caps"
        }
    }

    static func layer(forTrigger keyCode: KeyCode) -> LayerKey? {
        allCases.first { $0.triggerKeyCode == keyCode }
    }
}
