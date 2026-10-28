import Foundation

/// Right Command 를 어떻게 쓸지.
/// CapsLock Control 은 이걸 event tap 이 아니라 HID 리맵으로 처리하므로,
/// 값이 바뀌면 키보드 매핑을 다시 건다.
enum RightCommandAction: String, Codable, Hashable, Sendable, CaseIterable {
    /// F18 로 바꾼다 → macOS "이전 입력 소스 선택" (한/영 전환)
    case f18
    /// 건드리지 않는다. 평범한 오른쪽 ⌘ 로 남는다.
    case disabled = "none"

    var displayName: String {
        switch self {
        case .f18: "F18 (이전 입력 소스 선택)"
        case .disabled: "그대로 두기"
        }
    }
}

/// 디스크에 저장되는 설정 전체.
///
/// 레이어와 키는 **문자열 식별자**로 저장한다(`"capsLock"`, `"c"`, `"left"`).
/// 사람이 직접 열어서 고칠 수 있어야 하고, 가상 키코드 숫자는 읽을 수 없기 때문이다.
/// 실행 시점에 `makeBindingTable()` 이 키코드로 정규화한다.
struct CapsLockControlConfig: Codable, Equatable, Sendable {

    /// 이 앱이 이해하는 설정 버전. 파일이 이보다 높으면 읽기 전용으로 다룬다.
    static let currentVersion = 1

    struct Defaults: Codable, Equatable, Sendable {
        var whenAlreadyActive: AlreadyActiveBehavior
        /// 레이어가 켜진 상태에서 등록되지 않은 키를 눌렀을 때.
        var unmappedKeyPolicy: UnmappedKeyPolicy
        /// Caps Lock 을 **아무 키와도 조합하지 않고 짧게 눌렀다 떼면**
        /// 원래 기능(대문자 고정)을 토글한다.
        var capsLockTapTogglesCapsLock: Bool
        /// 위 판정의 시간 한도(밀리초). 이보다 오래 누르고 있었으면 탭이 아니다.
        var layerTapTimeoutMilliseconds: Int
        /// 새로 만드는 미디어 단축키가 명령을 보낼 곳.
        ///
        /// 개별 단축키마다 따로 지정할 수 있고, 이건 새로 만들 때의 출발점이다.
        /// `.system` 이면 하드웨어 미디어 키와 같은 경로라 브라우저의 유튜브도 받는다.
        var mediaTarget: MediaTarget

        static let defaultTapTimeout = 250

        init(whenAlreadyActive: AlreadyActiveBehavior = .hide,
             unmappedKeyPolicy: UnmappedKeyPolicy = CapsLockControlPolicy.unmappedKey,
             capsLockTapTogglesCapsLock: Bool = true,
             layerTapTimeoutMilliseconds: Int = Defaults.defaultTapTimeout,
             mediaTarget: MediaTarget = .system) {
            self.whenAlreadyActive = whenAlreadyActive
            self.unmappedKeyPolicy = unmappedKeyPolicy
            self.capsLockTapTogglesCapsLock = capsLockTapTogglesCapsLock
            self.layerTapTimeoutMilliseconds = layerTapTimeoutMilliseconds
            self.mediaTarget = mediaTarget
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            whenAlreadyActive = try c.decodeIfPresent(AlreadyActiveBehavior.self,
                                                      forKey: .whenAlreadyActive) ?? .hide
            unmappedKeyPolicy = try c.decodeIfPresent(UnmappedKeyPolicy.self,
                                                      forKey: .unmappedKeyPolicy)
                ?? CapsLockControlPolicy.unmappedKey
            capsLockTapTogglesCapsLock = try c.decodeIfPresent(
                Bool.self, forKey: .capsLockTapTogglesCapsLock) ?? true
            layerTapTimeoutMilliseconds = try c.decodeIfPresent(
                Int.self, forKey: .layerTapTimeoutMilliseconds) ?? Defaults.defaultTapTimeout
            // 이 키가 없던 시절의 설정 파일은 시스템 전체가 기본이었다. 그대로 읽는다.
            mediaTarget = try c.decodeIfPresent(MediaTarget.self, forKey: .mediaTarget) ?? .system
        }
    }

    /// 레이어와 무관한 모디파이어 재배치.
    struct ModifierConfig: Codable, Equatable, Sendable {
        /// fn 과 왼쪽 Control 을 맞바꾼다.
        ///
        /// Apple 키보드의 fn 은 일반 키보드 usage page 가 아니라
        /// Apple vendor top case page 에 있다. hidutil 이 그 페이지도 다뤄서
        /// 양방향 교환이 된다.
        var swapFnAndLeftControl: Bool

        init(swapFnAndLeftControl: Bool = false) {
            self.swapFnAndLeftControl = swapFnAndLeftControl
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // 빠져 있으면 끈 것으로 본다. 설정 파일에 없는 항목이 조용히
            // 키보드를 바꿔 버리면 안 된다.
            swapFnAndLeftControl = try c.decodeIfPresent(Bool.self,
                                                         forKey: .swapFnAndLeftControl) ?? false
        }
    }

    struct RightCommandConfig: Codable, Equatable, Sendable {
        var action: RightCommandAction

        init(action: RightCommandAction = .f18) {
            self.action = action
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            action = try c.decodeIfPresent(RightCommandAction.self, forKey: .action) ?? .f18
        }
    }

    var version: Int
    var defaults: Defaults
    var rightCommand: RightCommandConfig
    var modifiers: ModifierConfig
    /// 레이어 이름 → 키 식별자 → 동작
    var layers: [String: [String: ShortcutAction]]

    init(
        version: Int = CapsLockControlConfig.currentVersion,
        defaults: Defaults = Defaults(),
        rightCommand: RightCommandConfig = RightCommandConfig(),
        modifiers: ModifierConfig = ModifierConfig(),
        layers: [String: [String: ShortcutAction]] = [:]
    ) {
        self.version = version
        self.defaults = defaults
        self.rightCommand = rightCommand
        self.modifiers = modifiers
        self.layers = layers
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? CapsLockControlConfig.currentVersion
        defaults = try c.decodeIfPresent(Defaults.self, forKey: .defaults) ?? Defaults()
        rightCommand = try c.decodeIfPresent(RightCommandConfig.self, forKey: .rightCommand)
            ?? RightCommandConfig()
        modifiers = try c.decodeIfPresent(ModifierConfig.self, forKey: .modifiers) ?? ModifierConfig()
        layers = try c.decodeIfPresent([String: [String: ShortcutAction]].self, forKey: .layers) ?? [:]
    }
}

// MARK: - 조회 / 편집

extension CapsLockControlConfig {

    /// 문자열 식별자를 가상 키코드로 정규화한다.
    /// 알 수 없는 레이어 이름이나 키 식별자는 버리고 경고로 남긴다(죽지 않는다).
    func makeBindingTable() -> (table: BindingTable, warnings: [String]) {
        var result: [LayerKey: [KeyCode: ShortcutAction]] = [:]
        var warnings: [String] = []

        for (layerName, keys) in layers.sorted(by: { $0.key < $1.key }) {
            if LayerKey.retiredRawValues.contains(layerName) {
                // 빈 채로 남은 건 예전 기본 설정의 흔적일 뿐이다. 단축키가 있었다면 알린다.
                if !keys.isEmpty {
                    warnings.append("\(layerName) 레이어는 더 이상 쓰지 않습니다. "
                                    + "단축키 \(keys.count)개를 건너뜁니다.")
                }
                continue
            }
            guard let layer = LayerKey(rawValue: layerName) else {
                warnings.append("알 수 없는 레이어 \"\(layerName)\" 를 건너뜁니다.")
                continue
            }
            for (identifier, action) in keys.sorted(by: { $0.key < $1.key }) {
                guard let keyCode = KeyCodeTable.keyCode(forIdentifier: identifier) else {
                    warnings.append("\(layerName): 알 수 없는 키 \"\(identifier)\" 를 건너뜁니다.")
                    continue
                }
                if case .unsupported(let rawType) = action {
                    warnings.append("\(layerName)+\(identifier): 모르는 동작 타입 \"\(rawType)\"")
                }
                result[layer, default: [:]][keyCode] = action
            }
        }
        return (BindingTable(layers: result), warnings)
    }

    /// 키 하나의 동작.
    ///
    /// 저장된 키가 별칭(`","`)이고 찾는 쪽이 정식 이름(`"comma"`)이거나 그 반대일 수
    /// 있다. 같은 물리 키를 가리키면 찾아 준다.
    func action(layer: LayerKey, keyIdentifier: String) -> ShortcutAction? {
        guard let keys = layers[layer.rawValue] else { return nil }
        if let direct = keys[keyIdentifier] { return direct }
        guard let canonical = KeyCodeTable.canonicalIdentifier(keyIdentifier) else { return nil }
        if let byCanonical = keys[canonical] { return byCanonical }
        return keys.first { KeyCodeTable.canonicalIdentifier($0.key) == canonical }?.value
    }

    /// 키 하나에 동작을 걸거나 지운다.
    ///
    /// 저장할 때는 항상 정식 식별자를 쓴다. 사람이 손으로 `","` 라고 적어 둔 항목이
    /// 있으면 같이 지운다. 그대로 두면 같은 물리 키에 두 항목이 생겨서
    /// 어느 쪽이 이기는지 알 수 없게 된다.
    mutating func setAction(_ action: ShortcutAction?, layer: LayerKey, keyIdentifier: String) {
        let canonical = KeyCodeTable.canonicalIdentifier(keyIdentifier) ?? keyIdentifier
        var keys = layers[layer.rawValue] ?? [:]
        for existing in keys.keys where existing != canonical
            && KeyCodeTable.canonicalIdentifier(existing) == canonical {
            keys.removeValue(forKey: existing)
        }
        if let action {
            keys[canonical] = action
        } else {
            keys.removeValue(forKey: canonical)
        }
        layers[layer.rawValue] = keys
    }

    /// 이미 걸려 있는 미디어 단축키를 전부 한 대상으로 옮긴다.
    ///
    /// 하나씩 고치게 하면 재생/다음/이전을 세 번 눌러야 한다. 셋 다 같은 곳으로
    /// 보내고 싶은 게 보통이라 한 번에 옮길 길을 둔다.
    /// - Returns: 실제로 바뀐 개수.
    @discardableResult
    mutating func moveMediaShortcuts(to target: MediaTarget) -> Int {
        var changed = 0
        for layer in LayerKey.allCases {
            for (identifier, action) in sortedBindings(for: layer) {
                guard case .media(let command, let current) = action,
                      current != target else { continue }
                setAction(.media(command: command, target: target),
                          layer: layer, keyIdentifier: identifier)
                changed += 1
            }
        }
        return changed
    }

    /// 두 키의 동작을 맞바꾼다. 한쪽이 비어 있으면 "옮기기"가 된다.
    /// 어느 쪽도 잃지 않으므로 확인 없이 바로 적용해도 안전하다.
    mutating func swapActions(_ first: String, _ second: String, layer: LayerKey) {
        guard first != second else { return }
        let firstAction = action(layer: layer, keyIdentifier: first)
        let secondAction = action(layer: layer, keyIdentifier: second)
        setAction(secondAction, layer: layer, keyIdentifier: first)
        setAction(firstAction, layer: layer, keyIdentifier: second)
    }

    /// 정렬된 (키 식별자, 동작) 목록. UI 표시용.
    func sortedBindings(for layer: LayerKey) -> [(identifier: String, action: ShortcutAction)] {
        (layers[layer.rawValue] ?? [:])
            .map { (identifier: $0.key, action: $0.value) }
            .sorted { lhs, rhs in
                let order = KeyCodeTable.all.map(\.identifier)
                let l = order.firstIndex(of: lhs.identifier) ?? Int.max
                let r = order.firstIndex(of: rhs.identifier) ?? Int.max
                return l == r ? lhs.identifier < rhs.identifier : l < r
            }
    }
}
