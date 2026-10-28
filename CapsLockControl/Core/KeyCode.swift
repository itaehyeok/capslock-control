import Carbon.HIToolbox
import CoreGraphics

/// 하드웨어 "자리" 기반 가상 키코드.
///
/// 문자가 아니라 위치를 가리킨다. 한글 입력 상태이든 영문 상태이든
/// 같은 자리를 누르면 같은 KeyCode 가 온다. Karabiner 도 같은 방식이다.
struct KeyCode: Hashable, Sendable, Codable {
    let rawValue: CGKeyCode

    init(_ rawValue: CGKeyCode) { self.rawValue = rawValue }
    init(_ value: Int) { self.rawValue = CGKeyCode(truncatingIfNeeded: value) }
}

// MARK: - 이 앱이 특별 취급하는 키

extension KeyCode {
    /// 레이어 트리거. Caps Lock 을 HID 레벨에서 여기로 리맵한다.
    static let f19 = KeyCode(kVK_F19)
    /// 입력 소스 전환. Right Command 를 HID 레벨에서 여기로 리맵한다.
    static let f18 = KeyCode(kVK_F18)
}

// MARK: - 설정 파일/UI 에서 쓰는 문자열 식별자

/// `"c"`, `"3"`, `"comma"`, `"left"` 같은 안정적인 문자열 ↔ 가상 키코드 변환표.
///
/// 설정 JSON 과 QWERTY UI 가 공유한다. 새 키를 늘릴 때는 여기만 고치면 된다.
///
/// 기호 키는 `","` 같은 문자 대신 `"comma"` 처럼 이름으로 저장한다.
/// JSON 에서 `"\\"` 를 이스케이프해야 하는 번거로움을 피하려는 것이다.
/// 다만 사람이 손으로 `","` 라고 써도 읽히도록 별칭을 받아 준다.
enum KeyCodeTable {

    /// (식별자, 키코드, 화면 표시용 라벨)
    struct Entry: Sendable, Hashable {
        let identifier: String
        let keyCode: KeyCode
        let label: String
    }

    private static func entry(_ identifier: String, _ keyCode: Int, _ label: String) -> Entry {
        Entry(identifier: identifier, keyCode: KeyCode(keyCode), label: label)
    }

    static let numberRow: [Entry] = [
        entry("grave", kVK_ANSI_Grave, "`"),
        entry("1", kVK_ANSI_1, "1"),
        entry("2", kVK_ANSI_2, "2"),
        entry("3", kVK_ANSI_3, "3"),
        entry("4", kVK_ANSI_4, "4"),
        entry("5", kVK_ANSI_5, "5"),
        entry("6", kVK_ANSI_6, "6"),
        entry("7", kVK_ANSI_7, "7"),
        entry("8", kVK_ANSI_8, "8"),
        entry("9", kVK_ANSI_9, "9"),
        entry("0", kVK_ANSI_0, "0"),
        entry("minus", kVK_ANSI_Minus, "-"),
        entry("equal", kVK_ANSI_Equal, "="),
    ]

    static let topRow: [Entry] = [
        entry("q", kVK_ANSI_Q, "Q"),
        entry("w", kVK_ANSI_W, "W"),
        entry("e", kVK_ANSI_E, "E"),
        entry("r", kVK_ANSI_R, "R"),
        entry("t", kVK_ANSI_T, "T"),
        entry("y", kVK_ANSI_Y, "Y"),
        entry("u", kVK_ANSI_U, "U"),
        entry("i", kVK_ANSI_I, "I"),
        entry("o", kVK_ANSI_O, "O"),
        entry("p", kVK_ANSI_P, "P"),
        entry("leftBracket", kVK_ANSI_LeftBracket, "["),
        entry("rightBracket", kVK_ANSI_RightBracket, "]"),
        entry("backslash", kVK_ANSI_Backslash, "\\"),
    ]

    static let homeRow: [Entry] = [
        entry("a", kVK_ANSI_A, "A"),
        entry("s", kVK_ANSI_S, "S"),
        entry("d", kVK_ANSI_D, "D"),
        entry("f", kVK_ANSI_F, "F"),
        entry("g", kVK_ANSI_G, "G"),
        entry("h", kVK_ANSI_H, "H"),
        entry("j", kVK_ANSI_J, "J"),
        entry("k", kVK_ANSI_K, "K"),
        entry("l", kVK_ANSI_L, "L"),
        entry("semicolon", kVK_ANSI_Semicolon, ";"),
        entry("quote", kVK_ANSI_Quote, "'"),
    ]

    static let bottomRow: [Entry] = [
        entry("z", kVK_ANSI_Z, "Z"),
        entry("x", kVK_ANSI_X, "X"),
        entry("c", kVK_ANSI_C, "C"),
        entry("v", kVK_ANSI_V, "V"),
        entry("b", kVK_ANSI_B, "B"),
        entry("n", kVK_ANSI_N, "N"),
        entry("m", kVK_ANSI_M, "M"),
        entry("comma", kVK_ANSI_Comma, ","),
        entry("period", kVK_ANSI_Period, "."),
        entry("slash", kVK_ANSI_Slash, "/"),
    ]

    static let arrowCluster: [Entry] = [
        entry("left", kVK_LeftArrow, "←"),
        entry("up", kVK_UpArrow, "↑"),
        entry("down", kVK_DownArrow, "↓"),
        entry("right", kVK_RightArrow, "→"),
    ]

    /// 알파벳 블록 밖이지만 레이어 조합으로 쓸 만한 키들.
    static let extraCluster: [Entry] = [
        entry("space", kVK_Space, "␣"),
        entry("return", kVK_Return, "↩"),
        entry("tab", kVK_Tab, "⇥"),
        entry("delete", kVK_Delete, "⌫"),
        entry("escape", kVK_Escape, "esc"),
    ]

    /// QWERTY 에디터가 그리는 순서대로의 행 묶음.
    static let rows: [[Entry]] = [numberRow, topRow, homeRow, bottomRow]

    static let all: [Entry] = rows.flatMap { $0 } + arrowCluster + extraCluster

    /// 사람이 손으로 쓸 만한 별칭. 저장할 때는 항상 정식 식별자를 쓴다.
    private static let aliases: [String: String] = [
        "`": "grave", "-": "minus", "=": "equal",
        "[": "leftBracket", "]": "rightBracket", "\\": "backslash",
        ";": "semicolon", "'": "quote",
        ",": "comma", ".": "period", "/": "slash",
        " ": "space", "esc": "escape", "enter": "return", "backspace": "delete",
    ]

    /// `leftBracket` 처럼 대문자가 섞인 식별자도 대소문자 구분 없이 찾으려면
    /// 소문자로 접은 키로 저장해야 한다.
    private static let byFoldedIdentifier: [String: Entry] = {
        Dictionary(all.map { ($0.identifier.lowercased(), $0) },
                   uniquingKeysWith: { first, _ in first })
    }()

    private static let byKeyCode: [KeyCode: Entry] = {
        Dictionary(all.map { ($0.keyCode, $0) }, uniquingKeysWith: { first, _ in first })
    }()

    static func entry(forIdentifier identifier: String) -> Entry? {
        let folded = identifier.lowercased()
        if let direct = byFoldedIdentifier[folded] { return direct }
        guard let canonical = aliases[identifier] ?? aliases[folded] else { return nil }
        return byFoldedIdentifier[canonical.lowercased()]
    }

    static func entry(for keyCode: KeyCode) -> Entry? {
        byKeyCode[keyCode]
    }

    static func keyCode(forIdentifier identifier: String) -> KeyCode? {
        entry(forIdentifier: identifier)?.keyCode
    }

    static func identifier(for keyCode: KeyCode) -> String? {
        entry(for: keyCode)?.identifier
    }

    /// 별칭으로 들어온 식별자를 정식 이름으로 바꾼다. 설정을 저장할 때 쓴다.
    static func canonicalIdentifier(_ identifier: String) -> String? {
        entry(forIdentifier: identifier)?.identifier
    }
}
