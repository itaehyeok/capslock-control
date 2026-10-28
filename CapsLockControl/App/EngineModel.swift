import AppKit
import Observation
import os

/// UI 가 바라보는 엔진 · 설정 상태. 모든 접근은 MainActor.
@MainActor
@Observable
final class EngineModel {

    struct LogEntry: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let text: String
    }

    // MARK: - 공개 상태

    private(set) var logEntries: [LogEntry] = []
    private(set) var activeLayer: LayerKey?
    private(set) var isEngineRunning = false
    private(set) var isHIDMappingApplied = false
    private(set) var hidMappings: [HIDRemapper.Mapping] = []
    private(set) var isTrusted = AccessibilityPermission.isTrusted
    private(set) var conflictingApps: [KeyboardToolConflict] = []
    private(set) var lastError: String?

    private(set) var config: CapsLockControlConfig
    private(set) var configWarnings: [String] = []
    private(set) var isConfigReadOnly = false
    /// 설정에 있지만 이 Mac 에 설치되지 않은 앱들.
    private(set) var missingApplications: [String] = []

    var configFileURL: URL { store.fileURL }

    // MARK: - 내부

    @ObservationIgnored private let log = Logger(subsystem: "dev.itaehyeok.CapsLockControl", category: "Model")
    private static let maxLogEntries = 200

    @ObservationIgnored private let store = ConfigStore()
    @ObservationIgnored private var watchdog: Task<Void, Never>?

    // engine / executor 는 self 를 붙잡는 콜백을 들고 있다.
    // init 안에서 self 를 캡처할 수 없으므로 lazy 로 미뤄 둔다.
    // init 끝에서 applyConfigToEngine() 이 호출되는 순간 만들어진다.
    @ObservationIgnored private lazy var executor = ActionExecutor { [weak self] outcome in
        switch outcome {
        case .succeeded(let name): self?.appendLog("→ \(name)")
        case .failed(let message): self?.appendLog("⚠︎ \(message)")
        }
    }

    /// GitHub 설정 동기화. 설정 폴더 옆 `sync/` 에 clone 을 둔다.
    /// 설정 폴더 자체를 저장소로 만들지 않는 이유는, git 이 파일을 갈아치우는 동안
    /// 앱의 파일 감시자가 중간 상태를 읽을 수 있기 때문이다.
    @ObservationIgnored private(set) lazy var sync: SyncController = {
        let controller = SyncController(
            directory: store.directoryURL.appendingPathComponent("sync", isDirectory: true))
        controller.owner = self
        return controller
    }()

    /// 새 버전 확인과 설치.
    @ObservationIgnored let updates = UpdateController()

    @ObservationIgnored private lazy var engine = KeyboardEngine(
        observer: { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        },
        executeAction: { [weak self] _, _, action in
            Task { @MainActor in self?.executor.perform(action) }
        }
    )

    init() {
        let loaded = store.load(default: DefaultConfiguration.make)
        config = loaded.config
        configWarnings = loaded.warnings
        isConfigReadOnly = loaded.isReadOnly

        if loaded.didCreateFile {
            appendLog("설정 파일을 새로 만들었습니다: \(store.fileURL.path)")
        }
        for warning in loaded.warnings { appendLog("⚠︎ \(warning)") }

        applyConfigToEngine()
        startWatchingConfigFile()
        // lazy 로 만들어 두면 UI 가 처음 읽을 때까지 owner 가 비어 있다.
        _ = sync
    }

    // MARK: - 설정

    private func applyConfigToEngine() {
        let (table, warnings) = config.makeBindingTable()
        engine.updateConfiguration(
            bindings: table,
            hidMappings: HIDRemapper.mappings(for: config),
            options: EngineOptions(config: config)
        )
        executor.defaultWhenAlreadyActive = config.defaults.whenAlreadyActive
        hidMappings = engine.hidMappings
        for warning in warnings where !configWarnings.contains(warning) {
            configWarnings.append(warning)
            appendLog("⚠︎ \(warning)")
        }
        refreshMissingApplications()
    }

    /// 사람이 파일을 직접 고쳤을 때, 또는 "다시 불러오기" 버튼.
    func reloadConfig() {
        let loaded = store.load(default: DefaultConfiguration.make)
        // 우리가 방금 저장해서 생긴 변경이면 아무 일도 하지 않는다.
        guard loaded.config != config else { return }
        config = loaded.config
        configWarnings = loaded.warnings
        isConfigReadOnly = loaded.isReadOnly
        applyConfigToEngine()
        appendLog("설정을 다시 불러왔습니다 (단축키 \(engine.bindingCount)개).")
    }

    /// 되돌릴 수 없는 변경 직전에 지금 설정을 파일로 남긴다.
    @discardableResult
    func backUpCurrentConfig(reason: String) -> URL? {
        do {
            return try store.writeBackup(config, reason: reason)
        } catch {
            appendLog("⚠︎ 백업을 만들지 못했습니다: \(error.localizedDescription)")
            return nil
        }
    }

    var backupDirectoryURL: URL { store.backupDirectoryURL }

    /// 지금 설정을 사용자가 고른 위치에 파일로 남긴다. 설정 파일 자체는 건드리지 않는다.
    func exportConfig(to url: URL) throws {
        try ConfigFile.encode(config).write(to: url, options: [.atomic])
        appendLog("파일로 내보냈습니다 — \(url.lastPathComponent)")
    }

    /// 가져온 설정에서 고른 항목만 지금 설정에 반영한다.
    ///
    /// 되돌릴 수 없는 변경이므로 **적용 전에 항상 로컬 백업을 남긴다.**
    /// - Returns: 남긴 백업 파일. 바뀐 게 없거나 백업을 못 만들었으면 nil.
    @discardableResult
    func importItems(
        _ items: [ConfigDiff.Item],
        selecting selectedIDs: Set<String>,
        logPrefix: String
    ) -> URL? {
        guard !selectedIDs.isEmpty else { return nil }
        let updated = ConfigDiff.apply(items, selecting: selectedIDs, to: config)
        guard updated != config else { return nil }

        let backup = backUpCurrentConfig(reason: "before-import")
        saveConfig(updated)
        var message = "\(logPrefix) — \(selectedIDs.count)개 항목을 가져왔습니다"
        if let name = backup?.lastPathComponent {
            message += " (백업 \(name))"
        }
        appendLog(message)
        return backup
    }

    /// 설정 파일이 읽기 전용이면 GUI 편집을 막는다.
    var isEditable: Bool { !isConfigReadOnly }

    /// 키 하나에 동작을 걸거나(action) 지운다(nil). 즉시 파일에 저장된다.
    func setAction(_ action: ShortcutAction?, layer: LayerKey, keyIdentifier: String) {
        var updated = config
        updated.setAction(action, layer: layer, keyIdentifier: keyIdentifier)
        saveConfig(updated)
    }

    /// 키캡을 다른 키로 끌어다 놓았을 때. 양쪽 동작을 맞바꾼다(한쪽이 비면 이동).
    /// 저장은 한 번만 일어난다.
    func swapActions(_ first: String, _ second: String, layer: LayerKey) {
        var updated = config
        updated.swapActions(first, second, layer: layer)
        guard updated != config else { return }
        saveConfig(updated)
    }

    func setWhenAlreadyActiveDefault(_ behavior: AlreadyActiveBehavior) {
        guard config.defaults.whenAlreadyActive != behavior else { return }
        var updated = config
        updated.defaults.whenAlreadyActive = behavior
        saveConfig(updated)
    }

    /// Right Command 를 F18 로 쓸지 그대로 둘지. HID 매핑이 즉시 다시 걸린다.
    func setRightCommandAction(_ action: RightCommandAction) {
        guard config.rightCommand.action != action else { return }
        var updated = config
        updated.rightCommand.action = action
        saveConfig(updated)
    }

    func setUnmappedKeyPolicy(_ policy: UnmappedKeyPolicy) {
        guard config.defaults.unmappedKeyPolicy != policy else { return }
        var updated = config
        updated.defaults.unmappedKeyPolicy = policy
        saveConfig(updated)
    }

    /// fn 과 왼쪽 Control 맞바꾸기 on/off. 저장하면 HID 매핑이 즉시 다시 걸린다.
    func setSwapFnAndLeftControl(_ enabled: Bool) {
        guard config.modifiers.swapFnAndLeftControl != enabled else { return }
        var updated = config
        updated.modifiers.swapFnAndLeftControl = enabled
        saveConfig(updated)
    }

    /// 보낼 조합에 이름을 붙인다. 키캡에 "A" 대신 "NoCan 토글" 이 보이게 된다.
    func setKeyStrokeLabel(_ label: String?, layer: LayerKey, keyIdentifier: String) {
        guard case .keyStroke(var stroke) = config.action(layer: layer, keyIdentifier: keyIdentifier)
        else { return }
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        stroke.label = (trimmed?.isEmpty ?? true) ? nil : trimmed
        setAction(.keyStroke(stroke), layer: layer, keyIdentifier: keyIdentifier)
    }

    /// 키별 "이미 맨 앞일 때" 동작. nil 이면 전역 기본값을 따른다.
    /// 이 미디어 단축키가 명령을 보낼 곳을 바꾼다.
    ///
    /// `.system` 은 하드웨어 미디어 키와 같은 경로라, 브라우저에서 유튜브를 틀어 두면
    /// 그쪽이 받아 간다. Spotify 만 조종하려면 `.spotify` 로 바꾼다.
    func setMediaTarget(_ target: MediaTarget, layer: LayerKey, keyIdentifier: String) {
        guard case .media(let command, let current)? =
                config.action(layer: layer, keyIdentifier: keyIdentifier),
              current != target else { return }
        setAction(.media(command: command, target: target),
                  layer: layer, keyIdentifier: keyIdentifier)
    }

    /// 주어진 대상이 **아닌** 곳으로 향하는 미디어 단축키의 개수.
    /// "나머지도 옮기기" 버튼을 띄울지 판단하는 데 쓴다.
    func mediaShortcutCount(otherThan target: MediaTarget) -> Int {
        LayerKey.allCases.reduce(0) { total, layer in
            total + config.sortedBindings(for: layer).count { binding in
                if case .media(_, let current) = binding.action { current != target } else { false }
            }
        }
    }

    /// 새로 만드는 미디어 단축키의 기본 대상. 이미 만든 것은 건드리지 않는다.
    func setMediaTargetDefault(_ target: MediaTarget) {
        guard config.defaults.mediaTarget != target else { return }
        var updated = config
        updated.defaults.mediaTarget = target
        saveConfig(updated)
    }

    /// 이미 걸려 있는 미디어 단축키를 전부 한 대상으로 옮긴다.
    /// 하나씩 고치게 하면 세 개를 세 번 눌러야 한다.
    /// - Returns: 실제로 바뀐 개수.
    @discardableResult
    func moveAllMediaShortcuts(to target: MediaTarget) -> Int {
        var updated = config
        let changed = updated.moveMediaShortcuts(to: target)
        guard changed > 0 else { return 0 }
        saveConfig(updated)
        appendLog("미디어 단축키 \(changed)개를 \(target.displayName) 으로 옮겼습니다.")
        return changed
    }

    func setWhenAlreadyActive(
        _ behavior: AlreadyActiveBehavior?,
        layer: LayerKey,
        keyIdentifier: String
    ) {
        guard var target = config.action(layer: layer, keyIdentifier: keyIdentifier)?
            .applicationTarget else { return }
        target.whenAlreadyActive = behavior
        setAction(.application(target), layer: layer, keyIdentifier: keyIdentifier)
    }

    /// 저장 경로. GUI 편집과 수동 편집이 같은 함수를 쓴다.
    func saveConfig(_ newConfig: CapsLockControlConfig) {
        guard !isConfigReadOnly else {
            lastError = "설정 파일이 읽기 전용 상태입니다. 저장하지 않았습니다."
            return
        }
        do {
            try store.save(newConfig)
            config = newConfig
            applyConfigToEngine()
            appendLog("설정을 저장했습니다.")
        } catch {
            lastError = error.localizedDescription
            appendLog("⚠︎ \(error.localizedDescription)")
        }
    }

    private func startWatchingConfigFile() {
        store.startWatching { [weak self] in
            Task { @MainActor in self?.reloadConfig() }
        }
    }

    func revealConfigInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    /// 설치 여부는 LaunchServices 조회라서 뷰 본문에서 매번 부르면 안 된다.
    /// 설정이 바뀔 때 한 번만 계산해 두고 캐시를 본다.
    @ObservationIgnored private var missingBundleIdentifiers: Set<String> = []

    private func refreshMissingApplications() {
        var missingIDs: Set<String> = []
        var missingNames: Set<String> = []
        for layer in LayerKey.allCases {
            for binding in config.sortedBindings(for: layer) {
                guard let target = binding.action.applicationTarget else { continue }
                guard !DefaultConfiguration.isInstalled(bundleIdentifier: target.bundleIdentifier)
                else { continue }
                missingIDs.insert(target.bundleIdentifier)
                missingNames.insert(target.displayName.isEmpty
                                    ? target.bundleIdentifier : target.displayName)
            }
        }
        missingBundleIdentifiers = missingIDs
        missingApplications = missingNames.sorted()
        AppIconProvider.shared.invalidate(missingBundleIdentifiers: missingIDs)
    }

    func isInstalled(_ action: ShortcutAction) -> Bool {
        guard let target = action.applicationTarget else { return true }
        return !missingBundleIdentifiers.contains(target.bundleIdentifier)
    }

    var bindingCount: Int { engine.bindingCount }

    // MARK: - 엔진 제어

    func startIfPossible() {
        guard !engine.isRunning else { return }
        guard AccessibilityPermission.isTrusted else {
            isTrusted = false
            startPermissionWatchdog()
            return
        }
        do {
            try engine.start()
            lastError = nil
            appendLog("엔진을 시작했습니다 (단축키 \(engine.bindingCount)개).")
            // 데몬은 앱 실행 알림을 주지 않는다. 켜는 시점에 한 번 더 본다.
            refreshConflictingApps()
            for tool in conflictingApps where tool.isIntercepting {
                appendLog("⚠︎ \(tool.name) 이(가) 켜져 있습니다. 이 앱의 단축키가 안 먹을 수 있습니다.")
            }
        } catch {
            lastError = error.localizedDescription
            appendLog("⚠︎ 엔진 시작 실패: \(error.localizedDescription)")
        }
        refreshStatus()
    }

    func stop() {
        engine.stop()
        refreshStatus()
        appendLog("엔진을 정지했습니다. 키보드가 원래대로 돌아갑니다.")
    }

    func toggle() {
        if isEngineRunning { stop() } else { startIfPossible() }
    }

    func reapplyAfterWake() {
        engine.reapplyHIDMapping()
        refreshStatus()
    }

    /// 앱이 비정상 종료된 뒤 HID 매핑이 남았을 때의 수동 복구.
    func forceResetHIDMapping() {
        HIDRemapper().remove()
        refreshStatus()
        appendLog("HID 매핑을 강제로 해제했습니다.")
    }

    func requestAccessibilityPermission() {
        AccessibilityPermission.promptIfNeeded()
        AccessibilityPermission.openSystemSettings()
        startPermissionWatchdog()
    }

    func clearLog() { logEntries.removeAll() }

    /// UI 조작을 로그에 남긴다. 클릭이 먹었는지 눈으로 확인할 수 있게.
    func note(_ text: String) { appendLog(text) }

    // MARK: - 상태 갱신

    private func refreshStatus() {
        isEngineRunning = engine.isRunning
        isHIDMappingApplied = engine.isHIDMappingApplied
        hidMappings = engine.hidMappings
        activeLayer = engine.activeLayer
        isTrusted = AccessibilityPermission.isTrusted
    }

    /// 권한 허용 여부를 알려 주는 알림이 없어서 짧게 폴링한다.
    /// 허용되는 순간 자동으로 엔진을 띄운다.
    private func startPermissionWatchdog() {
        guard watchdog == nil else { return }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if AccessibilityPermission.isTrusted {
                    self.isTrusted = true
                    self.watchdog = nil
                    self.startIfPossible()
                    return
                }
            }
        }
    }

    /// 같은 키를 가로채는 다른 도구가 도는지 본다. **죽이지 않는다. 알려만 준다.**
    ///
    /// 예전에는 실행 중인 GUI 앱의 번들 ID 두 개와 `pgrep -f karabiner_grabber` 만 봤다.
    /// Karabiner 는 구성요소가 여럿이고 버전마다 프로세스 이름이 달라서 그걸로는 샌다.
    /// 그래서 전체 프로세스 목록을 훑는다.
    func refreshConflictingApps() {
        conflictingApps = KeyboardToolDetector.tools(in: Self.runningProcessList())
    }

    /// `ps` 로 전체 프로세스의 실행 파일 경로를 받는다. 실패하면 빈 문자열.
    private static func runningProcessList() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        // comm= 은 헤더 없이 실행 파일 경로만 낸다. root 로 도는 데몬도 보인다.
        process.arguments = ["-Ao", "comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self).lowercased()
        } catch {
            return ""
        }
    }

    // MARK: - 엔진 이벤트

    private func handle(_ event: EngineEvent) {
        switch event {
        case .layerChanged(let layer):
            activeLayer = layer
            appendLog(layer.map { "\($0.shortName) 레이어 ON" } ?? "레이어 OFF")
        case .performed(let layer, let key, let action):
            let keyLabel = KeyCodeTable.entry(for: key)?.label ?? "?"
            appendLog("\(layer.shortName) + \(keyLabel) → \(action.displayName)")
        case .swallowedUnmapped(let layer, let key):
            let keyLabel = KeyCodeTable.entry(for: key)?.label ?? "keycode \(key.rawValue)"
            appendLog("\(layer.shortName) + \(keyLabel) (등록 없음 · 무시)")
        case .stateReset(let reason):
            appendLog("상태 초기화: \(reason)")
        case .layerTapped(let layer):
            handleLayerTap(layer)
        case .hidMappingStateChanged(let isApplied, let errorMessage):
            isHIDMappingApplied = isApplied
            hidMappings = engine.hidMappings
            if let errorMessage {
                lastError = errorMessage
                appendLog("⚠︎ \(errorMessage)")
            }
        }
    }

    /// Caps Lock 을 단독으로 짧게 눌렀다 뗐을 때. 원래 기능을 토글한다.
    private func handleLayerTap(_ layer: LayerKey) {
        guard layer == .capsLock else { return }
        guard let isOn = CapsLockState.toggle() else {
            appendLog("⚠︎ Caps Lock 상태를 바꾸지 못했습니다")
            return
        }
        appendLog("Caps Lock \(isOn ? "켜짐" : "꺼짐")")
    }

    func setCapsLockTapEnabled(_ enabled: Bool) {
        guard config.defaults.capsLockTapTogglesCapsLock != enabled else { return }
        var updated = config
        updated.defaults.capsLockTapTogglesCapsLock = enabled
        saveConfig(updated)
    }

    /// Caps Lock 단독 탭으로 칠 시간 한도. 설정 창의 범위 밖 값은 범위 끝으로 맞춘다.
    func setLayerTapTimeout(milliseconds: Int) {
        let clamped = CapsLockControlConfig.Defaults.clampedTapTimeout(milliseconds)
        guard config.defaults.layerTapTimeoutMilliseconds != clamped else { return }
        var updated = config
        updated.defaults.layerTapTimeoutMilliseconds = clamped
        saveConfig(updated)
    }

    private func appendLog(_ text: String) {
        logEntries.append(LogEntry(timestamp: Date(), text: text))
        if logEntries.count > Self.maxLogEntries {
            logEntries.removeFirst(logEntries.count - Self.maxLogEntries)
        }
    }
}
