import Foundation

/// 설정 두 벌을 항목 단위로 비교한다.
///
/// Import 화면이 "무엇이 달라지는가" 를 보여 주고, 사용자가 고른 항목만
/// 가져오는 데 쓴다. 파일 전체를 갈아치우지 않고 골라 가져올 수 있는 이유가 이것이다.
enum ConfigDiff {

    /// 항목 하나의 값. 고른 쪽을 설정에 그대로 덮어쓸 수 있게 담아 둔다.
    enum Value: Sendable, Equatable {
        case binding(layer: LayerKey, key: String, action: ShortcutAction?)
        case whenAlreadyActive(AlreadyActiveBehavior)
        case unmappedKeyPolicy(UnmappedKeyPolicy)
        case rightCommand(RightCommandAction)
        case swapFnAndLeftControl(Bool)

        var description: String {
            switch self {
            case .binding(_, _, let action): action?.displayName ?? "없음"
            case .whenAlreadyActive(let behavior): behavior.displayName
            case .unmappedKeyPolicy(let policy): policy.displayName
            case .rightCommand(let action): action.displayName
            case .swapFnAndLeftControl(let enabled): enabled ? "켜짐" : "꺼짐"
            }
        }
    }

    struct Item: Identifiable, Sendable, Equatable {
        let id: String
        let label: String
        let current: Value
        let incoming: Value

        var currentDescription: String { current.description }
        var incomingDescription: String { incoming.description }

        /// 가져오면 새로 생기는 항목인지(현재는 비어 있음).
        var isAddition: Bool {
            if case .binding(_, _, let action) = current { return action == nil }
            return false
        }

        /// 가져오면 지워지는 항목인지.
        var isRemoval: Bool {
            if case .binding(_, _, let action) = incoming { return action == nil }
            return false
        }
    }

    // MARK: - 비교

    /// `current` 와 `incoming` 이 다른 항목만 돌려준다.
    /// 순서는 레이어 바인딩(키보드 순) → 스칼라 설정.
    static func items(current: CapsLockControlConfig, incoming: CapsLockControlConfig) -> [Item] {
        var items: [Item] = []
        let keyOrder = KeyCodeTable.all.map(\.identifier)

        for layer in LayerKey.allCases {
            let currentKeys = current.layers[layer.rawValue] ?? [:]
            let incomingKeys = incoming.layers[layer.rawValue] ?? [:]
            let allKeys = Set(currentKeys.keys).union(incomingKeys.keys)
            let sorted = allKeys.sorted { lhs, rhs in
                let l = keyOrder.firstIndex(of: lhs) ?? Int.max
                let r = keyOrder.firstIndex(of: rhs) ?? Int.max
                return l == r ? lhs < rhs : l < r
            }
            for key in sorted {
                let mine = currentKeys[key]
                let theirs = incomingKeys[key]
                guard mine != theirs else { continue }
                items.append(Item(
                    id: "binding.\(layer.rawValue).\(key)",
                    label: "\(layer.shortName) + \(keyLabel(key))",
                    current: .binding(layer: layer, key: key, action: mine),
                    incoming: .binding(layer: layer, key: key, action: theirs)
                ))
            }
        }

        appendSetting(&items,
                      id: "defaults.whenAlreadyActive",
                      label: "설정 · 앱이 이미 맨 앞일 때",
                      current: current.defaults.whenAlreadyActive,
                      incoming: incoming.defaults.whenAlreadyActive,
                      wrap: Value.whenAlreadyActive)
        appendSetting(&items,
                      id: "defaults.unmappedKeyPolicy",
                      label: "설정 · 등록되지 않은 키",
                      current: current.defaults.unmappedKeyPolicy,
                      incoming: incoming.defaults.unmappedKeyPolicy,
                      wrap: Value.unmappedKeyPolicy)
        appendSetting(&items,
                      id: "rightCommand.action",
                      label: "설정 · Right Command",
                      current: current.rightCommand.action,
                      incoming: incoming.rightCommand.action,
                      wrap: Value.rightCommand)
        appendSetting(&items,
                      id: "modifiers.swapFnAndLeftControl",
                      label: "설정 · fn ↔ 왼쪽 Control",
                      current: current.modifiers.swapFnAndLeftControl,
                      incoming: incoming.modifiers.swapFnAndLeftControl,
                      wrap: Value.swapFnAndLeftControl)

        return items
    }

    private static func appendSetting<T: Equatable>(
        _ items: inout [Item],
        id: String,
        label: String,
        current: T,
        incoming: T,
        wrap: (T) -> Value
    ) {
        guard current != incoming else { return }
        items.append(Item(id: id, label: label,
                          current: wrap(current), incoming: wrap(incoming)))
    }

    // MARK: - 적용

    /// 고른 항목만 가져온다. 고르지 않은 항목은 지금 설정을 유지한다.
    static func apply(
        _ items: [Item],
        selecting selectedIDs: Set<String>,
        to config: CapsLockControlConfig
    ) -> CapsLockControlConfig {
        var result = config
        for item in items where selectedIDs.contains(item.id) {
            apply(item.incoming, to: &result)
        }
        return result
    }

    static func apply(_ value: Value, to config: inout CapsLockControlConfig) {
        switch value {
        case .binding(let layer, let key, let action):
            config.setAction(action, layer: layer, keyIdentifier: key)
        case .whenAlreadyActive(let behavior):
            config.defaults.whenAlreadyActive = behavior
        case .unmappedKeyPolicy(let policy):
            config.defaults.unmappedKeyPolicy = policy
        case .rightCommand(let action):
            config.rightCommand.action = action
        case .swapFnAndLeftControl(let enabled):
            config.modifiers.swapFnAndLeftControl = enabled
        }
    }

    private static func keyLabel(_ identifier: String) -> String {
        KeyCodeTable.entry(forIdentifier: identifier)?.label ?? identifier
    }
}
