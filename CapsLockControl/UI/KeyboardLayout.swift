import Foundation

/// 키보드의 **물리적 생김새**. 어떤 키가 어느 자리에 얼마나 넓게 놓이는지만 다룬다.
///
/// `KeyCodeTable` 이 "어떤 키가 있는가"(의미)를 담당하고, 여기는 "어떻게 보이는가"를
/// 담당한다. 나눠 놓아야 shift 처럼 **단축키로 쓸 수 없는 키**를 그림에는 넣되
/// 바인딩 표에는 넣지 않을 수 있다.
enum KeyboardLayout {

    /// 키 한 칸의 기준 너비(1u)와 간격.
    static let unit: CGFloat = 46
    static let gap: CGFloat = 4
    static let keyHeight: CGFloat = 60

    /// 한 행의 총 유닛. 모든 행이 이 폭에 맞춰져 있어서 계단 모양이 어긋나지 않는다.
    static let totalUnits: CGFloat = 15.5

    static var totalWidth: CGFloat { width(totalUnits) }

    /// n유닛 키의 실제 픽셀 너비.
    ///
    /// 사이 간격까지 흡수해야 행마다 총 너비가 정확히 맞는다.
    /// (n유닛 키 = n칸 + 그 사이 간격 n-1개)
    static func width(_ units: CGFloat) -> CGFloat {
        units * unit + (units - 1) * gap
    }

    /// 단축키를 걸 수 없는 키. 모양만 그린다.
    struct FixedKey: Hashable {
        let label: String
        let role: Role

        enum Role: Hashable {
            /// 평범한 모디파이어. 회색으로만 그린다.
            case modifier
            /// 이 앱의 레이어 트리거. 보고 있는 레이어면 강조된다.
            case layerTrigger(LayerKey)
            /// 설정에 따라 F18 로 바뀌는 오른쪽 커맨드.
            case rightCommand
            /// fn ↔ 왼쪽 Control 스왑의 양쪽.
            case fnKey
            case leftControl
        }
    }

    /// 한 행에 같은 라벨의 키가 여러 번 나오므로(command, option, shift)
    /// 이 값만으로는 유일하지 않다. 그리는 쪽에서 위치로 구분한다.
    enum Element: Hashable {
        /// 단축키를 걸 수 있는 키. 값은 `KeyCodeTable` 의 식별자.
        case key(String, CGFloat)
        case fixed(FixedKey, CGFloat)
        /// ← ↑↓ → 묶음. 위아래가 반 높이로 겹쳐 쌓인다.
        case arrows

        var units: CGFloat {
            switch self {
            case .key(_, let units), .fixed(_, let units): units
            case .arrows: 3
            }
        }

        var isFixed: Bool {
            if case .fixed = self { return true }
            return false
        }
    }

    struct Row: Identifiable {
        let id: Int
        let elements: [Element]
        /// 모디파이어를 안 그릴 때 이 행을 얼마나 들여쓸지(유닛).
        /// 그냥 지우면 행이 왼쪽으로 몰려서 키보드처럼 보이지 않는다.
        let compactIndent: CGFloat
    }

    private static func modifier(_ label: String, _ units: CGFloat) -> Element {
        .fixed(FixedKey(label: label, role: .modifier), units)
    }

    /// 각 행의 총 너비가 15.5u 로 같다. 그래야 계단 모양이 어긋나지 않는다.
    static let rows: [Row] = [
        Row(id: 0, elements: [
            .key("escape", 1),
            .key("grave", 1),
            .key("1", 1), .key("2", 1), .key("3", 1), .key("4", 1), .key("5", 1),
            .key("6", 1), .key("7", 1), .key("8", 1), .key("9", 1), .key("0", 1),
            .key("minus", 1), .key("equal", 1),
            .key("delete", 1.5),
        ], compactIndent: 0),

        Row(id: 1, elements: [
            .key("tab", 2),
            .key("q", 1), .key("w", 1), .key("e", 1), .key("r", 1), .key("t", 1),
            .key("y", 1), .key("u", 1), .key("i", 1), .key("o", 1), .key("p", 1),
            .key("leftBracket", 1), .key("rightBracket", 1),
            .key("backslash", 1.5),
        ], compactIndent: 0),

        Row(id: 2, elements: [
            .fixed(FixedKey(label: "caps lock", role: .layerTrigger(.capsLock)), 2),
            .key("a", 1), .key("s", 1), .key("d", 1), .key("f", 1), .key("g", 1),
            .key("h", 1), .key("j", 1), .key("k", 1), .key("l", 1),
            .key("semicolon", 1), .key("quote", 1),
            .key("return", 2.5),
        ], compactIndent: 1),

        Row(id: 3, elements: [
            modifier("shift", 2.5),
            .key("z", 1), .key("x", 1), .key("c", 1), .key("v", 1), .key("b", 1),
            .key("n", 1), .key("m", 1),
            .key("comma", 1), .key("period", 1), .key("slash", 1),
            modifier("shift", 3),
        ], compactIndent: 1.5),

        Row(id: 4, elements: [
            .fixed(FixedKey(label: "fn", role: .fnKey), 1),
            .fixed(FixedKey(label: "control", role: .leftControl), 1),
            modifier("option", 1),
            modifier("command", 1.5),
            // 맥북처럼 스페이스가 C 왼쪽 모서리에서 M 오른쪽 모서리까지 온다.
            // 위 행이 shift(2.5) + Z X 이므로 C 는 4.5u, M 은 9.5u 에서 끝난다.
            .key("space", 5),
            // 스페이스 오른쪽이 오른쪽 커맨드다. 설정에 따라 F18 로 바뀐다.
            .fixed(FixedKey(label: "command", role: .rightCommand), 1.5),
            modifier("option", 1),
            .arrows,
        ], compactIndent: 3.5),
    ]

    /// 모디파이어를 그릴지 여부에 따라 실제로 그릴 요소를 돌려준다.
    static func elements(of row: Row, showingFixedKeys: Bool) -> [Element] {
        showingFixedKeys ? row.elements : row.elements.filter { !$0.isFixed }
    }

    static func indent(of row: Row, showingFixedKeys: Bool) -> CGFloat {
        showingFixedKeys ? 0 : row.compactIndent
    }

    /// 들여쓰기의 픽셀 값.
    static func indentWidth(_ units: CGFloat) -> CGFloat {
        units <= 0 ? 0 : units * unit + units * gap
    }
}
