import Foundation
import Testing
@testable import CapsLockControl

private func app(_ bundleID: String, _ name: String) -> ShortcutAction {
    .application(ApplicationTarget(bundleIdentifier: bundleID, displayName: name))
}

private let chrome = app("com.google.Chrome", "Google Chrome")
private let safari = app("com.apple.Safari", "Safari")
private let notion = app("notion.id", "Notion")

private func config(_ bindings: [String: ShortcutAction]) -> CapsLockControlConfig {
    var config = CapsLockControlConfig()
    for (key, action) in bindings {
        config.setAction(action, layer: .capsLock, keyIdentifier: key)
    }
    return config
}

@Suite("설정 비교와 골라 가져오기")
struct ConfigDiffTests {

    @Test("같으면 가져올 것이 없다")
    func identicalConfigsHaveNoItems() {
        let same = config(["c": chrome, "s": safari])
        #expect(ConfigDiff.items(current: same, incoming: same).isEmpty)
    }

    @Test("스냅샷에만 있는 항목은 추가로 표시된다")
    func additionIsLabelled() {
        let items = ConfigDiff.items(current: config([:]), incoming: config(["c": chrome]))
        #expect(items.count == 1)
        #expect(items[0].label == "Caps + C")
        #expect(items[0].isAddition)
        #expect(!items[0].isRemoval)
        #expect(items[0].currentDescription == "없음")
        #expect(items[0].incomingDescription == "Google Chrome")
    }

    @Test("지금만 있는 항목은 삭제로 표시된다")
    func removalIsLabelled() {
        let items = ConfigDiff.items(current: config(["c": chrome]), incoming: config([:]))
        #expect(items.count == 1)
        #expect(items[0].isRemoval)
        #expect(!items[0].isAddition)
    }

    @Test("값만 다르면 변경이다")
    func changeIsNeitherAdditionNorRemoval() {
        let items = ConfigDiff.items(current: config(["c": chrome]), incoming: config(["c": safari]))
        #expect(items.count == 1)
        #expect(!items[0].isAddition)
        #expect(!items[0].isRemoval)
    }

    @Test("체크한 항목만 가져오고 나머지는 그대로 둔다")
    func onlySelectedItemsAreApplied() {
        let current = config(["c": chrome, "s": safari])
        let incoming = config(["c": notion, "s": notion])
        let items = ConfigDiff.items(current: current, incoming: incoming)
        #expect(items.count == 2)

        guard let capsC = items.first(where: { $0.label == "Caps + C" }) else {
            Issue.record("Caps + C 항목이 없습니다")
            return
        }
        let applied = ConfigDiff.apply(items, selecting: [capsC.id], to: current)
        #expect(applied.action(layer: .capsLock, keyIdentifier: "c") == notion)
        // 고르지 않은 쪽은 건드리지 않는다.
        #expect(applied.action(layer: .capsLock, keyIdentifier: "s") == safari)
    }

    @Test("아무것도 안 고르면 설정이 그대로다")
    func selectingNothingChangesNothing() {
        let current = config(["c": chrome])
        let items = ConfigDiff.items(current: current, incoming: config(["c": safari]))
        #expect(ConfigDiff.apply(items, selecting: [], to: current) == current)
    }

    @Test("전체를 고르면 바인딩이 스냅샷과 같아진다")
    func selectingEverythingMatchesSnapshot() {
        let current = config(["c": chrome, "z": notion])
        let incoming = config(["c": safari, "s": notion])
        let items = ConfigDiff.items(current: current, incoming: incoming)
        let applied = ConfigDiff.apply(items, selecting: Set(items.map(\.id)), to: current)

        #expect(applied.action(layer: .capsLock, keyIdentifier: "c") == safari)
        #expect(applied.action(layer: .capsLock, keyIdentifier: "s") == notion)
        // 스냅샷에 없던 z 는 삭제 항목이었으므로 함께 사라진다.
        #expect(applied.action(layer: .capsLock, keyIdentifier: "z") == nil)
        #expect(ConfigDiff.items(current: applied, incoming: incoming).isEmpty)
    }

    @Test("스칼라 설정도 항목으로 나온다")
    func scalarSettingsBecomeItems() {
        var current = CapsLockControlConfig()
        var incoming = CapsLockControlConfig()
        incoming.defaults.whenAlreadyActive = .switchToPrevious
        incoming.modifiers.swapFnAndLeftControl = true
        incoming.rightCommand.action = .f18
        incoming.defaults.unmappedKeyPolicy = .passThrough

        let items = ConfigDiff.items(current: current, incoming: incoming)
        #expect(items.count == 4)

        // fn 스왑만 골라서 가져온다.
        guard let fnItem = items.first(where: { $0.id == "modifiers.swapFnAndLeftControl" }) else {
            Issue.record("fn 스왑 항목이 없습니다")
            return
        }
        let applied = ConfigDiff.apply(items, selecting: [fnItem.id], to: current)
        #expect(applied.modifiers.swapFnAndLeftControl)
        #expect(applied.defaults.whenAlreadyActive == .hide)
        #expect(applied.rightCommand.action == .disabled)
    }

    @Test("바인딩이 설정보다 먼저, 키보드 순서로 나온다")
    func itemsAreOrdered() {
        var current = CapsLockControlConfig()
        var incoming = CapsLockControlConfig()
        incoming.defaults.whenAlreadyActive = .nothing
        for key in ["z", "a", "1"] {
            incoming.setAction(chrome, layer: .capsLock, keyIdentifier: key)
        }
        let labels = ConfigDiff.items(current: current, incoming: incoming).map(\.label)
        #expect(labels == ["Caps + 1", "Caps + A", "Caps + Z", "설정 · 앱이 이미 맨 앞일 때"])
    }

    @Test("항목 id 는 겹치지 않는다")
    func identifiersAreUnique() {
        var incoming = CapsLockControlConfig()
        for key in KeyCodeTable.all.prefix(20).map(\.identifier) {
            incoming.setAction(chrome, layer: .capsLock, keyIdentifier: key)
        }
        incoming.defaults.whenAlreadyActive = .nothing
        let ids = ConfigDiff.items(current: CapsLockControlConfig(), incoming: incoming).map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
