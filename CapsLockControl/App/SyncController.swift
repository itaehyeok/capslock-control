import CryptoKit
import Foundation
import Observation
import os

enum SyncState: Equatable, Sendable {
    case notConfigured
    case idle
    case working(String)
    case failed(String)
}

/// GitHub 설정 동기화. **Export / Import** 두 동작으로 되어 있다.
///
/// 왜 자동 병합이 아니라 이 방식인가:
/// - Export 는 지우는 게 없다. 매번 시각과 Mac 이름이 붙은 **새 스냅샷**이 쌓인다.
///   그래서 잘못 올려도 이전 상태가 그대로 남아 있고, 되돌리는 게 Import 한 번이다.
/// - Import 는 무엇이 달라지는지 보여 주고 **항목을 골라** 가져올 수 있다.
///   자동 병합이 표현할 수 없는 "회사 Mac 의 Caps+C 만 가져오기" 가 가능하다.
/// - 공통 조상을 추적할 필요가 없어서 조용히 틀리는 경로가 없다.
///
/// 대가는 자동이 아니라는 것이다. 그래서 "내보낼 변경 있음" 을 상태로 알려 준다.
@MainActor
@Observable
final class SyncController {

    private enum Key {
        static let remoteURL = "sync.remoteURL"
        static let lastExportedAt = "sync.lastExportedAt"
        static let lastExportedDigest = "sync.lastExportedDigest"
    }

    private(set) var state: SyncState = .notConfigured
    private(set) var snapshots: [GitSync.SnapshotRef] = []
    /// Import 화면이 열려 있는지. 메뉴바에서도 켤 수 있어야 해서 여기 둔다.
    var isImportSheetPresented = false
    private(set) var lastBackupURL: URL?
    private(set) var lastExportedAt: Date?
    private(set) var lastSummary: String?

    var remoteURL: String {
        didSet {
            UserDefaults.standard.set(remoteURL, forKey: Key.remoteURL)
            state = remoteURL.isEmpty ? .notConfigured : .idle
        }
    }

    private let log = Logger(subsystem: "dev.itaehyeok.CapsLockControl", category: "Sync")
    private let directory: URL

    /// 설정을 읽고 쓰는 주체는 EngineModel 이다. 순환 참조를 피하려고 약하게 잡는다.
    weak var owner: EngineModel?

    init(directory: URL) {
        self.directory = directory
        let stored = UserDefaults.standard.string(forKey: Key.remoteURL) ?? ""
        remoteURL = stored
        lastExportedAt = UserDefaults.standard.object(forKey: Key.lastExportedAt) as? Date
        state = stored.isEmpty ? .notConfigured : .idle
    }

    var isConfigured: Bool { !remoteURL.isEmpty }

    var isWorking: Bool {
        if case .working = state { return true }
        return false
    }

    // MARK: - 상태 표시

    func statusLine(for config: CapsLockControlConfig) -> String {
        switch state {
        case .notConfigured: "Sync: 설정 안 됨"
        case .working(let step): "Sync: \(step)"
        case .failed: "Sync: 오류"
        case .idle: hasUnexportedChanges(config) ? "내보낼 변경 있음" : "✓ 내보낸 상태와 같음"
        }
    }

    /// 마지막 Export 이후 설정이 바뀌었는지. 내용 해시로 판단한다.
    /// 한 번도 내보내지 않았으면 내보낼 것이 있는 상태로 본다.
    func hasUnexportedChanges(_ config: CapsLockControlConfig) -> Bool {
        guard let stored = UserDefaults.standard.string(forKey: Key.lastExportedDigest) else {
            return true
        }
        return digest(of: config) != stored
    }

    private func digest(of config: CapsLockControlConfig) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func makeSync() -> GitSync {
        GitSync(remoteURL: remoteURL, directory: directory)
    }

    // MARK: - Export

    func export() async {
        guard isConfigured, let owner, !isWorking else { return }
        let config = owner.config
        do {
            state = .working("저장소 준비 중")
            let sync = makeSync()
            try await sync.prepare()

            state = .working("GitHub 에 올리는 중")
            let snapshot = try await sync.export(config)

            let now = Date()
            lastExportedAt = now
            UserDefaults.standard.set(now, forKey: Key.lastExportedAt)
            UserDefaults.standard.set(digest(of: config), forKey: Key.lastExportedDigest)
            lastSummary = snapshot.displayName
            state = .idle
            owner.note("Export 완료 — \(snapshot.displayName)")
            // 방금 올린 것이 목록에 보이게 갱신한다.
            snapshots.insert(snapshot, at: 0)
        } catch {
            state = .failed(error.localizedDescription)
            owner.note("⚠︎ Export 실패: \(error.localizedDescription)")
            log.error("export 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Import

    /// 저장소에 쌓인 스냅샷 목록을 받아 온다.
    func refreshSnapshots() async {
        guard isConfigured, let owner, !isWorking else { return }
        do {
            state = .working("목록 가져오는 중")
            let sync = makeSync()
            try await sync.prepare()
            snapshots = try await sync.listSnapshots()
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
            owner.note("⚠︎ 목록을 가져오지 못했습니다: \(error.localizedDescription)")
        }
    }

    /// 스냅샷을 지금 설정과 비교한다. 가져오기 전에 무엇이 달라지는지 보여 주기 위해서다.
    func diff(for reference: GitSync.SnapshotRef) async -> [ConfigDiff.Item]? {
        guard isConfigured, let owner else { return nil }
        do {
            state = .working("스냅샷 읽는 중")
            let snapshot = try await makeSync().loadSnapshot(reference)
            state = .idle
            return ConfigDiff.items(current: owner.config, incoming: snapshot)
        } catch {
            state = .failed(error.localizedDescription)
            owner.note("⚠︎ 스냅샷을 읽지 못했습니다: \(error.localizedDescription)")
            return nil
        }
    }

    /// 메뉴바에서 Import 화면을 연다. 설정 창이 없으면 함께 띄운다.
    func requestImportSheet() {
        isImportSheetPresented = true
        WindowOpener.shared.openSettings()
    }

    /// 고른 항목만 지금 설정에 반영한다. GitHub 에는 아무것도 올리지 않는다.
    /// 로컬 백업은 `EngineModel.importItems` 가 적용 전에 항상 남긴다.
    func importItems(_ items: [ConfigDiff.Item], selecting selectedIDs: Set<String>) {
        guard let owner else { return }
        lastBackupURL = owner.importItems(items, selecting: selectedIDs, logPrefix: "Import 완료")
        state = .idle
    }

    /// 지금 설정을 GitHub 에 스냅샷으로 올린 다음 가져온다.
    /// Export 가 실패하면 가져오지 않는다. 되돌릴 방법을 못 만든 채 덮어쓰면 안 된다.
    /// - Returns: 가져오기까지 마쳤으면 true.
    func exportThenImport(_ items: [ConfigDiff.Item], selecting selectedIDs: Set<String>) async -> Bool {
        await export()
        if case .failed = state { return false }
        importItems(items, selecting: selectedIDs)
        return true
    }

    var backupDirectoryURL: URL? { owner?.backupDirectoryURL }
}
