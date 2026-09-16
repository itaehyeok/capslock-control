import Foundation

/// 레이어가 켜진 상태에서 "등록되지 않은" 키를 눌렀을 때의 정책.
///
/// 기본값은 `.swallow`. Caps 를 누른 채로 아무 키나 눌렀을 때
/// 엉뚱한 글자가 입력되는 사고를 막는 쪽이 안전하다.
/// 정책을 바꾸고 싶으면 `CapsLockControlPolicy.unmappedKey` 한 줄만 고치면 된다.
enum UnmappedKeyPolicy: String, Codable, Sendable {
    /// 원본 이벤트를 버린다. 아무 일도 일어나지 않는다. (기본)
    case swallow
    /// 원본 이벤트를 그대로 앱에 전달한다.
    case passThrough
}

extension UnmappedKeyPolicy: CaseIterable {
    static var allCases: [UnmappedKeyPolicy] { [.swallow, .passThrough] }

    var displayName: String {
        switch self {
        case .swallow: "무시하기 (안전)"
        case .passThrough: "원래 키 입력"
        }
    }

    var explanation: String {
        switch self {
        case .swallow: "레이어를 누른 채 등록 안 된 키를 눌러도 아무 글자가 입력되지 않습니다."
        case .passThrough: "등록 안 된 키는 평소처럼 입력됩니다. 실수로 글자가 섞일 수 있습니다."
        }
    }
}

enum CapsLockControlPolicy {
    /// 설정 파일에 값이 없을 때 쓰는 기본값.
    static let unmappedKey: UnmappedKeyPolicy = .swallow
}
