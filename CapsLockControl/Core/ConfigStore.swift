import Foundation
import os

enum ConfigStoreError: LocalizedError {
    case readOnlyNewerVersion(found: Int, supported: Int)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .readOnlyNewerVersion(let found, let supported):
            "설정 파일 버전이 \(found) 인데 이 앱은 \(supported) 까지 압니다. "
            + "덮어쓰면 새 버전에서 만든 내용이 사라지므로 저장하지 않습니다."
        case .writeFailed(let reason):
            "설정을 저장하지 못했습니다: \(reason)"
        }
    }
}

/// `~/Library/Application Support/CapsLockControl/shortcuts.json` 을 읽고 쓴다.
///
/// - 저장은 항상 atomic. 중간에 죽어도 파일이 반쪽으로 남지 않는다.
/// - 파일이 깨져 있으면 지우지 않고 백업해 둔 뒤 기본값으로 시작한다.
/// - 파일 버전이 앱보다 높으면 읽기 전용으로 취급한다(다른 Mac 에서 만든 설정 보호).
/// - 폴더를 감시해서 사람이 직접 고치면 자동으로 다시 읽는다.
final class ConfigStore: @unchecked Sendable {

    struct LoadResult: Sendable {
        var config: CapsLockControlConfig
        var warnings: [String]
        var isReadOnly: Bool
        /// 깨진 파일을 옮겨 둔 위치.
        var backupURL: URL?
        /// 파일이 없어서 새로 만들었는지.
        var didCreateFile: Bool
    }

    let directoryURL: URL
    let fileURL: URL

    private let log = Logger(subsystem: "dev.itaehyeok.CapsLockControl", category: "Config")
    private let queue = DispatchQueue(label: "dev.itaehyeok.CapsLockControl.config")
    private var watchSource: DispatchSourceFileSystemObject?
    private var pendingChange: DispatchWorkItem?

    init(directoryURL: URL? = nil) {
        let base = directoryURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CapsLockControl", isDirectory: true)
        self.directoryURL = base
        self.fileURL = base.appendingPathComponent("shortcuts.json")
    }

    // MARK: - 읽기

    func load(default makeDefault: () -> CapsLockControlConfig) -> LoadResult {
        ensureDirectoryExists()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let config = makeDefault()
            var warnings: [String] = []
            do {
                try write(config)
            } catch {
                warnings.append("기본 설정을 저장하지 못했습니다: \(error.localizedDescription)")
            }
            return LoadResult(config: config, warnings: warnings,
                              isReadOnly: false, backupURL: nil, didCreateFile: true)
        }

        do {
            let data = try Data(contentsOf: fileURL)
            var config = try JSONDecoder().decode(CapsLockControlConfig.self, from: data)
            var warnings: [String] = []

            if config.version > CapsLockControlConfig.currentVersion {
                let error = ConfigStoreError.readOnlyNewerVersion(
                    found: config.version, supported: CapsLockControlConfig.currentVersion)
                warnings.append(error.localizedDescription)
                return LoadResult(config: config, warnings: warnings,
                                  isReadOnly: true, backupURL: nil, didCreateFile: false)
            }

            let (migrated, migrationWarnings) = Self.migrate(config)
            config = migrated
            warnings.append(contentsOf: migrationWarnings)

            return LoadResult(config: config, warnings: warnings,
                              isReadOnly: false, backupURL: nil, didCreateFile: false)
        } catch {
            // 깨진 설정. 지우지 않고 옮겨 둔다.
            let backup = backUpBrokenFile()
            log.error("설정 파일을 읽지 못했습니다: \(error.localizedDescription)")
            let config = makeDefault()
            var warnings = [
                "설정 파일을 읽지 못해 기본값으로 시작합니다: \(error.localizedDescription)"
            ]
            if let backup {
                warnings.append("원본은 \(backup.lastPathComponent) 로 보관했습니다.")
            }
            try? write(config)
            return LoadResult(config: config, warnings: warnings,
                              isReadOnly: false, backupURL: backup, didCreateFile: true)
        }
    }

    /// 앞으로 스키마가 바뀌면 여기에 단계별 변환을 넣는다.
    private static func migrate(_ config: CapsLockControlConfig) -> (CapsLockControlConfig, [String]) {
        var config = config
        var warnings: [String] = []
        // 현재는 v1 뿐이라 할 일이 없다. 버전만 최신으로 맞춰 둔다.
        if config.version < CapsLockControlConfig.currentVersion {
            warnings.append("설정을 v\(config.version) → v\(CapsLockControlConfig.currentVersion) 로 올렸습니다.")
            config.version = CapsLockControlConfig.currentVersion
        }
        return (config, warnings)
    }

    // MARK: - 쓰기

    func save(_ config: CapsLockControlConfig) throws {
        guard config.version <= CapsLockControlConfig.currentVersion else {
            throw ConfigStoreError.readOnlyNewerVersion(
                found: config.version, supported: CapsLockControlConfig.currentVersion)
        }
        try write(config)
    }

    private func write(_ config: CapsLockControlConfig) throws {
        ensureDirectoryExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(config)
            // .atomic 은 임시 파일에 쓴 뒤 rename 한다. 중간 상태가 남지 않는다.
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw ConfigStoreError.writeFailed(error.localizedDescription)
        }
    }

    /// 되돌릴 수 없는 변경(Import 등) 직전에 지금 설정을 남겨 둔다.
    /// 네트워크와 무관하게 항상 성공해야 하는 안전망이라 로컬 파일로 쓴다.
    @discardableResult
    func writeBackup(_ config: CapsLockControlConfig, reason: String) throws -> URL {
        let backupDirectory = directoryURL.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let url = backupDirectory
            .appendingPathComponent("\(formatter.string(from: Date()))_\(reason).json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(config).write(to: url, options: [.atomic])
        log.info("백업 저장: \(url.lastPathComponent, privacy: .public)")
        return url
    }

    var backupDirectoryURL: URL {
        directoryURL.appendingPathComponent("backups", isDirectory: true)
    }

    private func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func backUpBrokenFile() -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backup = directoryURL.appendingPathComponent("shortcuts.broken-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: backup)
            return backup
        } catch {
            log.error("깨진 설정 파일을 백업하지 못했습니다: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 파일 감시

    /// 폴더를 감시한다. 파일이 아니라 폴더를 보는 이유는, atomic 저장이 파일을
    /// 새 inode 로 갈아치우기 때문에 파일 감시는 한 번 쓰고 끊기기 때문이다.
    func startWatching(onChange: @escaping @Sendable () -> Void) {
        queue.async { [weak self] in
            guard let self, self.watchSource == nil else { return }
            self.ensureDirectoryExists()
            let descriptor = open(self.directoryURL.path, O_EVTONLY)
            guard descriptor >= 0 else {
                self.log.error("설정 폴더를 감시할 수 없습니다.")
                return
            }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write], queue: self.queue)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                // 에디터가 저장할 때 이벤트가 여러 번 온다. 한 번으로 합친다.
                self.pendingChange?.cancel()
                let work = DispatchWorkItem { onChange() }
                self.pendingChange = work
                self.queue.asyncAfter(deadline: .now() + 0.3, execute: work)
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            self.watchSource = source
        }
    }

    func stopWatching() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingChange?.cancel()
            self.pendingChange = nil
            self.watchSource?.cancel()
            self.watchSource = nil
        }
    }
}
