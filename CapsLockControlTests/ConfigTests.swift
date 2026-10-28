import CoreGraphics
import Foundation
import Testing
@testable import CapsLockControl

@Suite("설정 파일 모델")
struct CapsLockControlConfigTests {

    @Test("전체 설정이 왕복한다")
    func roundTrip() throws {
        var config = CapsLockControlConfig()
        config.setAction(
            .application(ApplicationTarget(bundleIdentifier: "com.google.Chrome",
                                           displayName: "Google Chrome",
                                           whenAlreadyActive: .switchToPrevious)),
            layer: .capsLock, keyIdentifier: "c")
        config.setAction(.media(command: .next, target: .system),
                         layer: .capsLock, keyIdentifier: "right")

        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(CapsLockControlConfig.self, from: data) == config)
    }

    @Test("빠진 필드는 기본값으로 채워진다")
    func missingFieldsGetDefaults() throws {
        let json = Data(#"{"layers":{"capsLock":{}}}"#.utf8)
        let config = try JSONDecoder().decode(CapsLockControlConfig.self, from: json)
        #expect(config.version == CapsLockControlConfig.currentVersion)
        #expect(config.defaults.whenAlreadyActive == .hide)
        #expect(config.rightCommand.action == .disabled)
    }

    @Test("rightCommand 를 none 으로 끌 수 있다")
    func rightCommandCanBeDisabled() throws {
        let json = Data(#"{"rightCommand":{"action":"none"}}"#.utf8)
        let config = try JSONDecoder().decode(CapsLockControlConfig.self, from: json)
        #expect(config.rightCommand.action == .disabled)
    }

    @Test("모르는 레이어와 키는 버리고 경고만 남긴다")
    func unknownEntriesBecomeWarnings() {
        var config = CapsLockControlConfig()
        config.layers = [
            "capsLock": [
                "c": .application(ApplicationTarget(bundleIdentifier: "com.google.Chrome",
                                                    displayName: "Chrome")),
                "F13": .application(ApplicationTarget(bundleIdentifier: "x", displayName: "X")),
            ],
            "middleClick": [
                "a": .application(ApplicationTarget(bundleIdentifier: "y", displayName: "Y")),
            ],
        ]
        let (table, warnings) = config.makeBindingTable()
        #expect(table.count == 1)
        #expect(warnings.count == 2)
        #expect(table.layers[.capsLock]?.count == 1)
    }

    @Test("단축키 목록은 키보드 배열 순서로 정렬된다")
    func bindingsAreSortedByKeyboardOrder() {
        var config = CapsLockControlConfig()
        for key in ["z", "a", "q", "1"] {
            config.setAction(.media(command: .playPause, target: .system),
                             layer: .capsLock, keyIdentifier: key)
        }
        let order = config.sortedBindings(for: .capsLock).map(\.identifier)
        #expect(order == ["1", "q", "a", "z"])
    }

    @Test("키캡을 옮기면 두 키의 동작이 맞바뀐다")
    func swapMovesBothWays() {
        var config = CapsLockControlConfig()
        let chrome = ShortcutAction.application(
            ApplicationTarget(bundleIdentifier: "com.google.Chrome", displayName: "Chrome"))
        let safari = ShortcutAction.application(
            ApplicationTarget(bundleIdentifier: "com.apple.Safari", displayName: "Safari"))
        config.setAction(chrome, layer: .capsLock, keyIdentifier: "c")
        config.setAction(safari, layer: .capsLock, keyIdentifier: "s")

        config.swapActions("c", "s", layer: .capsLock)
        #expect(config.action(layer: .capsLock, keyIdentifier: "c") == safari)
        #expect(config.action(layer: .capsLock, keyIdentifier: "s") == chrome)
    }

    @Test("빈 키로 옮기면 원래 키가 비워진다")
    func swapWithEmptyKeyMoves() {
        var config = CapsLockControlConfig()
        let chrome = ShortcutAction.application(
            ApplicationTarget(bundleIdentifier: "com.google.Chrome", displayName: "Chrome"))
        config.setAction(chrome, layer: .capsLock, keyIdentifier: "c")

        config.swapActions("c", "x", layer: .capsLock)
        #expect(config.action(layer: .capsLock, keyIdentifier: "x") == chrome)
        #expect(config.action(layer: .capsLock, keyIdentifier: "c") == nil)
        #expect(config.sortedBindings(for: .capsLock).count == 1)
    }

    @Test("같은 키끼리 옮기면 아무 일도 없다")
    func swapWithSelfIsNoOp() {
        var config = CapsLockControlConfig()
        let chrome = ShortcutAction.application(
            ApplicationTarget(bundleIdentifier: "com.google.Chrome", displayName: "Chrome"))
        config.setAction(chrome, layer: .capsLock, keyIdentifier: "c")
        let before = config
        config.swapActions("c", "c", layer: .capsLock)
        #expect(config == before)
    }

    @Test("기호 키를 문자로 적어 둬도 GUI 가 고치면 이름으로 정리된다")
    func aliasKeysAreNormalizedOnWrite() {
        var config = CapsLockControlConfig()
        // 사람이 손으로 "," 라고 적어 둔 상태.
        config.layers = ["capsLock": [",": .media(command: .next, target: .system)]]
        #expect(config.action(layer: .capsLock, keyIdentifier: "comma")
                == .media(command: .next, target: .system))

        // GUI 로 같은 키를 고치면 정식 이름 하나만 남아야 한다.
        let chrome = ShortcutAction.application(
            ApplicationTarget(bundleIdentifier: "com.google.Chrome", displayName: "Chrome"))
        config.setAction(chrome, layer: .capsLock, keyIdentifier: ",")
        #expect(config.layers["capsLock"]?.keys.sorted() == ["comma"])
        #expect(config.action(layer: .capsLock, keyIdentifier: "comma") == chrome)

        // 바인딩 표에도 중복이 생기지 않는다.
        let (table, _) = config.makeBindingTable()
        #expect(table.count == 1)
    }

    @Test("HID 매핑 목록이 rightCommand 설정을 따라간다")
    func hidMappingsFollowConfig() {
        var config = CapsLockControlConfig()
        #expect(HIDRemapper.mappings(for: config).count == 1)

        config.rightCommand.action = .f18
        let mappings = HIDRemapper.mappings(for: config)
        #expect(mappings.count == 2)
        #expect(mappings.contains(HIDRemapper.rightCommandToF18))
    }

    @Test("fn ↔ 왼쪽 Control 스왑은 켤 때만 매핑에 들어간다")
    func fnControlSwapIsOptional() {
        var config = CapsLockControlConfig()
        #expect(config.modifiers.swapFnAndLeftControl == false)
        #expect(HIDRemapper.mappings(for: config).count == 1)

        config.modifiers.swapFnAndLeftControl = true
        let mappings = HIDRemapper.mappings(for: config)
        #expect(mappings.count == 3)
        // 양방향이어야 한다. 한쪽만 걸면 두 키가 모두 Control 이 된다.
        #expect(mappings.contains { $0.source == HIDRemapper.HIDUsage.fn
                                 && $0.destination == HIDRemapper.HIDUsage.leftControl })
        #expect(mappings.contains { $0.source == HIDRemapper.HIDUsage.leftControl
                                 && $0.destination == HIDRemapper.HIDUsage.fn })
    }

    @Test("설정 파일에 modifiers 가 없으면 스왑은 꺼진 것으로 읽는다")
    func missingModifierSectionDefaultsOff() throws {
        // 파일에 없는 항목이 조용히 키보드를 바꿔 버리면 안 된다.
        let json = Data(#"{"version":1,"layers":{}}"#.utf8)
        let config = try JSONDecoder().decode(CapsLockControlConfig.self, from: json)
        #expect(config.modifiers.swapFnAndLeftControl == false)
    }

}

@Suite("설정 파일 저장소")
struct ConfigStoreTests {

    /// 테스트마다 새 임시 폴더를 쓴다. 실제 설정 파일은 건드리지 않는다.
    private func makeStore() -> ConfigStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapsLockControlTests-\(UUID().uuidString)", isDirectory: true)
        return ConfigStore(directoryURL: directory)
    }

    private func cleanUp(_ store: ConfigStore) {
        try? FileManager.default.removeItem(at: store.directoryURL)
    }

    @Test("파일이 없으면 기본 설정을 만들어 저장한다")
    func createsDefaultWhenMissing() {
        let store = makeStore()
        defer { cleanUp(store) }

        let expected = CapsLockControlConfig()
        let result = store.load(default: { expected })
        #expect(result.didCreateFile)
        #expect(result.config == expected)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test("저장한 설정이 그대로 다시 읽힌다")
    func saveThenLoad() throws {
        let store = makeStore()
        defer { cleanUp(store) }

        var config = CapsLockControlConfig()
        config.setAction(.application(ApplicationTarget(bundleIdentifier: "md.obsidian",
                                                        displayName: "Obsidian")),
                         layer: .capsLock, keyIdentifier: "d")
        try store.save(config)

        let result = store.load(default: { CapsLockControlConfig() })
        #expect(!result.didCreateFile)
        #expect(result.config == config)
        #expect(!result.isReadOnly)
    }

    @Test("깨진 파일은 지우지 않고 백업한 뒤 기본값으로 시작한다")
    func brokenFileIsBackedUp() throws {
        let store = makeStore()
        defer { cleanUp(store) }

        try FileManager.default.createDirectory(at: store.directoryURL,
                                                withIntermediateDirectories: true)
        try Data("{ this is not json".utf8).write(to: store.fileURL)

        let result = store.load(default: { CapsLockControlConfig() })
        #expect(result.backupURL != nil)
        #expect(!result.warnings.isEmpty)
        if let backup = result.backupURL {
            #expect(FileManager.default.fileExists(atPath: backup.path))
        }
        // 기본값으로 새 파일이 만들어져 있어야 한다.
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test("더 새로운 버전의 파일은 읽기 전용이고 저장을 거부한다")
    func newerVersionIsReadOnly() throws {
        let store = makeStore()
        defer { cleanUp(store) }

        try FileManager.default.createDirectory(at: store.directoryURL,
                                                withIntermediateDirectories: true)
        let future = CapsLockControlConfig(version: CapsLockControlConfig.currentVersion + 5)
        try Data(JSONEncoder().encode(future)).write(to: store.fileURL)

        let result = store.load(default: { CapsLockControlConfig() })
        #expect(result.isReadOnly)
        #expect(!result.warnings.isEmpty)
        #expect(throws: ConfigStoreError.self) { try store.save(future) }
    }
}

@Suite("기본 설정 생성")
struct DefaultConfigurationTests {

    @Test("처음에는 단축키가 하나도 없다")
    func startsEmpty() {
        let config = DefaultConfiguration.make()
        let (table, warnings) = config.makeBindingTable()
        #expect(warnings.isEmpty)
        #expect(table.count == 0)
        // 레이어는 만들어 두되 비어 있다.
        #expect(config.layers[LayerKey.capsLock.rawValue]?.isEmpty == true)
        #expect(config.layers.count == 1)
    }

    @Test("예전 Right Option 레이어가 비어 있으면 경고 없이 건너뛴다")
    func emptyRetiredLayerIsSilent() throws {
        let json = #"{"layers": {"capsLock": {}, "rightOption": {}}}"#
        let config = try JSONDecoder().decode(CapsLockControlConfig.self, from: Data(json.utf8))
        let (table, warnings) = config.makeBindingTable()
        #expect(warnings.isEmpty)
        #expect(table.count == 0)
    }

    @Test("예전 Right Option 레이어에 단축키가 있으면 알리고 건너뛴다")
    func filledRetiredLayerWarns() throws {
        let json = #"""
        {"layers": {"rightOption": {"d": {"type": "application", "bundleIdentifier": "md.obsidian"}}}}
        """#
        let config = try JSONDecoder().decode(CapsLockControlConfig.self, from: Data(json.utf8))
        let (table, warnings) = config.makeBindingTable()
        #expect(table.count == 0)
        #expect(warnings.count == 1)
    }

    @Test("키보드를 바꾸는 설정은 꺼진 채로 시작한다")
    func keyboardAlteringDefaultsAreOff() {
        // 남의 Mac 에서 첫 실행했는데 fn 과 Control 이 바뀌어 있으면 곤란하다.
        #expect(DefaultConfiguration.make().modifiers.swapFnAndLeftControl == false)
    }

    @Test("Right Command 는 건드리지 않은 채로 시작한다")
    func rightCommandDefault() {
        // F18 은 macOS 단축키를 따로 지정해야 쓸모가 있다. 모르고 켜지면 오른쪽 ⌘ 만 사라진다.
        #expect(DefaultConfiguration.make().rightCommand.action == .disabled)
    }

    @Test("설정 파일에 rightCommand 가 없으면 건드리지 않는 것으로 읽는다")
    func missingRightCommandDefaultsOff() throws {
        let json = Data(#"{"version":1,"layers":{}}"#.utf8)
        let config = try JSONDecoder().decode(CapsLockControlConfig.self, from: json)
        #expect(config.rightCommand.action == .disabled)
    }

    @Test("Caps Lock 단독 탭은 켜진 채로 시작한다")
    func capsLockTapIsOnByDefault() {
        // 키에 적힌 대로 동작하는 게 기본값으로 자연스럽다.
        let defaults = DefaultConfiguration.make().defaults
        #expect(defaults.capsLockTapTogglesCapsLock)
        #expect(defaults.layerTapTimeoutMilliseconds == 250)
    }

    @Test("빠진 필드는 안전한 값으로 읽힌다")
    func missingTapFieldsDecodeSafely() throws {
        let json = Data(#"{"version":1,"defaults":{},"layers":{}}"#.utf8)
        let config = try JSONDecoder().decode(CapsLockControlConfig.self, from: json)
        #expect(config.defaults.capsLockTapTogglesCapsLock)
        #expect(config.defaults.layerTapTimeoutMilliseconds == 250)
        #expect(config.modifiers.swapFnAndLeftControl == false)
    }

    @Test("엔진 옵션이 설정을 그대로 옮긴다")
    func engineOptionsMirrorConfig() {
        var config = CapsLockControlConfig()
        config.defaults.capsLockTapTogglesCapsLock = false
        config.defaults.layerTapTimeoutMilliseconds = 400
        config.defaults.unmappedKeyPolicy = .passThrough

        let options = EngineOptions(config: config)
        #expect(options.capsLockTapTogglesCapsLock == false)
        #expect(options.layerTapTimeout == 0.4)
        #expect(options.unmappedKeyPolicy == .passThrough)
    }

    @Test("탭 판정 시간은 설정 창 범위 안으로 맞춘다")
    func tapTimeoutIsClamped() {
        typealias Defaults = CapsLockControlConfig.Defaults
        #expect(Defaults.tapTimeoutRange.contains(Defaults.defaultTapTimeout))
        #expect(Defaults.clampedTapTimeout(300) == 300)
        #expect(Defaults.clampedTapTimeout(0) == Defaults.tapTimeoutRange.lowerBound)
        #expect(Defaults.clampedTapTimeout(5000) == Defaults.tapTimeoutRange.upperBound)
    }
}

@Suite("키 조합 보내기")
struct KeyStrokeTests {

    @Test("조합이 왕복하고 수정자 순서는 정규화된다")
    func roundTripAndNormalization() throws {
        let stroke = KeyStroke(keyIdentifier: "a",
                               modifiers: [.shift, .control, .option],
                               label: "NoCan 토글")
        // 입력 순서와 무관하게 ⌃⌥⇧⌘ 순서로 정리된다.
        #expect(stroke.modifiers == [.control, .option, .shift])

        let action = ShortcutAction.keyStroke(stroke)
        let data = try JSONEncoder().encode(action)
        #expect(try JSONDecoder().decode(ShortcutAction.self, from: data) == action)
    }

    @Test("수정자 순서가 달라도 같은 조합이다")
    func modifierOrderDoesNotMatter() {
        let first = KeyStroke(keyIdentifier: "a", modifiers: [.control, .option, .shift])
        let second = KeyStroke(keyIdentifier: "a", modifiers: [.shift, .option, .control])
        #expect(first == second)
    }

    @Test("표시 문자열이 macOS 관례를 따른다")
    func comboString() {
        #expect(KeyStroke(keyIdentifier: "a",
                          modifiers: [.control, .option, .shift]).comboString == "⌃⌥⇧A")
        #expect(KeyStroke(keyIdentifier: "comma",
                          modifiers: [.command]).comboString == "⌘,")
        #expect(KeyStroke(keyIdentifier: "space", modifiers: []).comboString == "␣")
        // 이름을 붙이면 이름과 조합이 함께 보인다.
        #expect(KeyStroke(keyIdentifier: "a", modifiers: [.command], label: "Toggle")
                .displayName == "Toggle (⌘A)")
        #expect(KeyStroke(keyIdentifier: "a", modifiers: [.command]).displayName == "⌘A")
    }

    @Test("modifiers 가 없는 JSON 도 읽힌다")
    func decodesWithoutModifiers() throws {
        let json = Data(#"{"type":"keyStroke","key":"escape"}"#.utf8)
        #expect(try JSONDecoder().decode(ShortcutAction.self, from: json)
                == .keyStroke(KeyStroke(keyIdentifier: "escape", modifiers: [])))
    }

    @Test("CGEvent 플래그로 정확히 옮겨진다")
    func flagMapping() {
        #expect(KeyStrokeSender.cgEventFlags(for: []).isEmpty)
        #expect(KeyStrokeSender.cgEventFlags(for: [.control, .option, .shift])
                == [.maskControl, .maskAlternate, .maskShift])
        #expect(KeyStrokeSender.cgEventFlags(for: [.command]) == .maskCommand)
        #expect(KeyStrokeSender.cgEventFlags(for: KeyStrokeModifier.allCases)
                == [.maskControl, .maskAlternate, .maskShift, .maskCommand])
    }

    @Test("합성 이벤트 표시가 이벤트에 실리고 그대로 읽힌다")
    func syntheticMarkerSurvives() throws {
        // 무한 루프 방지가 전적으로 이 필드에 달려 있다.
        // Caps+A → 조합 발생 → 탭이 다시 잡음 → 또 발생 ... 을 막는 유일한 수단이다.
        let source = CGEventSource(stateID: .privateState)
        let event = try #require(CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true))
        event.flags = [.maskControl, .maskAlternate, .maskShift]
        event.setIntegerValueField(.eventSourceUserData, value: KeyStrokeSender.syntheticMarker)

        #expect(event.getIntegerValueField(.eventSourceUserData) == KeyStrokeSender.syntheticMarker)
        #expect(event.flags == [.maskControl, .maskAlternate, .maskShift])

        // 표시가 없는 평범한 이벤트는 값이 다르다.
        let plain = try #require(CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true))
        #expect(plain.getIntegerValueField(.eventSourceUserData) != KeyStrokeSender.syntheticMarker)
    }

    @Test("설정에 넣으면 바인딩 표에 경고 없이 들어간다")
    func fitsIntoBindingTable() {
        var config = CapsLockControlConfig()
        config.setAction(
            .keyStroke(KeyStroke(keyIdentifier: "a", modifiers: [.control, .option, .shift],
                                 label: "NoCan 토글")),
            layer: .capsLock, keyIdentifier: "a")
        let (table, warnings) = config.makeBindingTable()
        #expect(warnings.isEmpty)
        #expect(table.count == 1)
    }
}

@Suite("git 경로 파싱")
struct GitPathParsingTests {

    @Test("ASCII 경로는 그대로 돌려준다")
    func plainPathIsUnchanged() {
        let path = "snapshots/2026-09-16_101834_my-macbook.json"
        #expect(GitSync.unquotePath(path) == path)
    }

    @Test("따옴표로 감싸고 8진 이스케이프한 한글 경로를 되돌린다")
    func quotedKoreanPathIsDecoded() {
        // core.quotepath 기본값(true)에서 git 이 내놓는 형태.
        // 이걸 못 되돌려서 스냅샷 목록이 통째로 비어 보였다.
        let raw = "\"snapshots/2026-09-14_105547_user\\354\\235\\230-MacBook-Pro.json\""
        let decoded = GitSync.unquotePath(raw)
        #expect(decoded == "snapshots/2026-09-14_105547_user의-MacBook-Pro.json")
        #expect(decoded.hasSuffix(".json"))
    }

    @Test("이스케이프된 따옴표와 역슬래시를 되돌린다")
    func escapedCharactersAreDecoded() {
        #expect(GitSync.unquotePath("\"a\\\"b.json\"") == "a\"b.json")
        #expect(GitSync.unquotePath("\"a\\\\b.json\"") == "a\\b.json")
    }

    @Test("따옴표가 한쪽만 있으면 건드리지 않는다")
    func halfQuotedIsLeftAlone() {
        #expect(GitSync.unquotePath("\"broken.json") == "\"broken.json")
        #expect(GitSync.unquotePath("") == "")
    }
}
