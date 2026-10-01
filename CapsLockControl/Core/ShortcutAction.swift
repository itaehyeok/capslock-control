import Foundation

/// 대상 앱이 이미 맨 앞에 있을 때 같은 단축키를 다시 눌렀을 때의 동작.
enum AlreadyActiveBehavior: String, Codable, Hashable, Sendable, CaseIterable {
    /// 아무것도 하지 않는다(그냥 계속 앞에 있다).
    case nothing
    /// 앱을 숨긴다. ⌘H 와 같고, macOS 가 알아서 다음 앱을 활성화한다.
    case hide
    /// 이 앱 바로 직전에 앞에 있던 앱으로 되돌아간다.
    case switchToPrevious

    var displayName: String {
        switch self {
        case .nothing: "아무것도 안 함"
        case .hide: "숨기기 (⌘H)"
        case .switchToPrevious: "직전 앱으로"
        }
    }
}

/// 실행할 앱. 항상 bundle identifier 로 저장한다.
/// `bundleURLPath` 는 캐시된 힌트일 뿐이라 신뢰하지 않고, 실행 시점에 다시 조회한다.
struct ApplicationTarget: Codable, Hashable, Sendable {
    var bundleIdentifier: String
    var displayName: String
    var bundleURLPath: String?
    /// nil 이면 설정의 전역 기본값을 따른다.
    var whenAlreadyActive: AlreadyActiveBehavior?

    init(
        bundleIdentifier: String,
        displayName: String,
        bundleURLPath: String? = nil,
        whenAlreadyActive: AlreadyActiveBehavior? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.bundleURLPath = bundleURLPath
        self.whenAlreadyActive = whenAlreadyActive
    }
}

/// 다른 앱에 보낼 키 조합의 수정자.
enum KeyStrokeModifier: String, Codable, Hashable, Sendable, CaseIterable {
    case control, option, shift, command

    /// 화면 표시 순서는 macOS 관례(⌃⌥⇧⌘)를 따른다.
    var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    static let displayOrder: [KeyStrokeModifier] = [.control, .option, .shift, .command]
}

/// 다른 앱의 전역 단축키를 건드리기 위해 CapsLock Control 이 대신 눌러 주는 키 조합.
///
/// Caps Lock 은 이 앱에서 F19 로 바뀌기 때문에 다른 앱이 "Caps+A" 를 직접 등록할
/// 수 없다. 대신 Caps+A 를 CapsLock Control 이 받아서 이 조합을 발생시키면, 그 조합을
/// 등록해 둔 앱(Carbon RegisterEventHotKey 등)이 평소처럼 반응한다.
struct KeyStroke: Codable, Hashable, Sendable {
    /// `KeyCodeTable` 의 키 식별자. 예: "a", "comma", "space"
    var keyIdentifier: String
    var modifiers: [KeyStrokeModifier]
    /// UI 에 보여 줄 이름. 예: "NoCan 토글"
    var label: String?

    init(keyIdentifier: String, modifiers: [KeyStrokeModifier], label: String? = nil) {
        self.keyIdentifier = keyIdentifier
        // 순서가 저장 결과를 흔들지 않도록 정규화한다.
        self.modifiers = KeyStrokeModifier.displayOrder.filter(modifiers.contains)
        self.label = label
    }

    /// "⌃⌥⇧A" 같은 표기.
    var comboString: String {
        let symbols = KeyStrokeModifier.displayOrder
            .filter(modifiers.contains).map(\.symbol).joined()
        let key = KeyCodeTable.entry(forIdentifier: keyIdentifier)?.label
            ?? keyIdentifier.uppercased()
        return symbols + key
    }

    var displayName: String {
        guard let label, !label.isEmpty else { return comboString }
        return "\(label) (\(comboString))"
    }
}

enum MediaCommand: String, Codable, Hashable, Sendable {
    case playPause
    case next
    case previous
}

/// 미디어 명령을 누구에게 보낼지.
/// `.system` 은 하드웨어 미디어 키와 같은 경로 → 지금 재생 중인 앱이 받는다.
/// `.spotify` 는 Spotify 에 직접 AppleScript 를 보낸다(자동화 권한 필요).
/// `.youTubeMusic` 은 Chrome 의 YouTube Music 탭에 직접 보낸다(자동화 권한 +
/// Chrome 의 "Apple Events의 자바스크립트 허용" 필요).
enum MediaTarget: String, Codable, Hashable, Sendable, CaseIterable {
    case system
    case spotify
    case youTubeMusic

    var displayName: String {
        switch self {
        case .system: "시스템 전체"
        case .spotify: "Spotify 전용"
        case .youTubeMusic: "YouTube Music 전용"
        }
    }

    /// 왜 이걸 고르는지 한 줄. 고르는 자리에 같이 띄운다.
    var detail: String {
        switch self {
        case .system:
            "재생 중인 아무 앱이나 받습니다 — 브라우저의 유튜브도 포함입니다."
        case .spotify:
            "Spotify 에만 보냅니다. 유튜브는 반응하지 않습니다. "
            + "처음 쓸 때 자동화 권한을 한 번 물어봅니다."
        case .youTubeMusic:
            "Chrome 에 열린 YouTube Music 탭에만 보냅니다. 다른 유튜브 탭은 반응하지 않습니다. "
            + "Chrome 의 보기 › 개발자 › Apple Events의 자바스크립트 허용을 켜 두어야 하고, "
            + "처음 쓸 때 자동화 권한을 한 번 물어봅니다."
        }
    }
}

/// 하나의 키에 붙는 동작.
///
/// v1 은 `application` 과 `media` 만 구현한다.
/// 앞으로 url / shellCommand / appleScript / file 을 추가할 자리를 열어 둔 형태다.
enum ShortcutAction: Codable, Hashable, Sendable {
    case application(ApplicationTarget)
    case media(command: MediaCommand, target: MediaTarget)
    /// 다른 앱의 전역 단축키를 부르기 위해 키 조합을 발생시킨다.
    case keyStroke(KeyStroke)
    /// 이 버전이 모르는 action type. 설정 파일을 읽다 만나도 죽지 않기 위한 자리.
    case unsupported(rawType: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case bundleIdentifier, displayName, bundleURLPath, whenAlreadyActive
        case command, target
        case key, modifiers, label
    }

    private enum Kind: String {
        case application, media, keyStroke
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try c.decode(String.self, forKey: .type)
        switch Kind(rawValue: rawType) {
        case .application:
            self = .application(ApplicationTarget(
                bundleIdentifier: try c.decode(String.self, forKey: .bundleIdentifier),
                displayName: try c.decodeIfPresent(String.self, forKey: .displayName) ?? "",
                bundleURLPath: try c.decodeIfPresent(String.self, forKey: .bundleURLPath),
                whenAlreadyActive: try c.decodeIfPresent(AlreadyActiveBehavior.self, forKey: .whenAlreadyActive)
            ))
        case .media:
            self = .media(
                command: try c.decode(MediaCommand.self, forKey: .command),
                target: try c.decodeIfPresent(MediaTarget.self, forKey: .target) ?? .system
            )
        case .keyStroke:
            self = .keyStroke(KeyStroke(
                keyIdentifier: try c.decode(String.self, forKey: .key),
                modifiers: try c.decodeIfPresent([KeyStrokeModifier].self, forKey: .modifiers) ?? [],
                label: try c.decodeIfPresent(String.self, forKey: .label)
            ))
        case nil:
            self = .unsupported(rawType: rawType)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .application(let app):
            try c.encode(Kind.application.rawValue, forKey: .type)
            try c.encode(app.bundleIdentifier, forKey: .bundleIdentifier)
            try c.encode(app.displayName, forKey: .displayName)
            try c.encodeIfPresent(app.bundleURLPath, forKey: .bundleURLPath)
            try c.encodeIfPresent(app.whenAlreadyActive, forKey: .whenAlreadyActive)
        case .media(let command, let target):
            try c.encode(Kind.media.rawValue, forKey: .type)
            try c.encode(command, forKey: .command)
            try c.encode(target, forKey: .target)
        case .keyStroke(let stroke):
            try c.encode(Kind.keyStroke.rawValue, forKey: .type)
            try c.encode(stroke.keyIdentifier, forKey: .key)
            try c.encode(stroke.modifiers, forKey: .modifiers)
            try c.encodeIfPresent(stroke.label, forKey: .label)
        case .unsupported(let rawType):
            try c.encode(rawType, forKey: .type)
        }
    }
}

extension ShortcutAction {
    /// 키캡/메뉴에 보여줄 짧은 이름.
    var displayName: String {
        switch self {
        case .application(let app):
            app.displayName.isEmpty ? app.bundleIdentifier : app.displayName
        case .media(let command, _):
            switch command {
            case .playPause: "Play/Pause"
            case .next: "Next"
            case .previous: "Previous"
            }
        case .keyStroke(let stroke):
            stroke.displayName
        case .unsupported(let rawType):
            "Unsupported (\(rawType))"
        }
    }

    var applicationTarget: ApplicationTarget? {
        if case .application(let target) = self { return target }
        return nil
    }
}
