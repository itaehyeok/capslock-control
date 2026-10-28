import AppKit
import Observation
import os

/// 새 버전 확인과 설치. 화면(메뉴바·창·설정)이 이걸 바라본다.
///
/// 확인은 알아서 하고, 설치는 사람이 누를 때만 한다. 키보드를 다루는 앱이라
/// 타자 치는 도중에 저절로 꺼졌다 켜지면 곤란하다.
@MainActor
@Observable
final class UpdateController {

    enum CheckResult: Equatable {
        case upToDate
        case available
        /// 묻지 못했다(오프라인, 조회 한도 등).
        case failed
    }

    /// 나와 있는 새 버전. 없으면 nil.
    private(set) var available: UpdateCheck.Release?
    private(set) var isChecking = false
    private(set) var isInstalling = false
    /// 마지막 설치 실패 이유. 누른 자리에 적는다.
    private(set) var installFailure: String?
    private(set) var lastCheckedAt: Date?
    private(set) var lastResult: CheckResult?

    /// 켤 때 한 번, 그 뒤로는 이 간격마다. 몇 주씩 켜 두는 앱이라 켤 때만 보면 새 버전을 모른다.
    static let checkInterval: Duration = .seconds(6 * 60 * 60)
    /// 창을 열 때마다 묻지 않게 둔 최소 간격.
    static let minimumGap: TimeInterval = 5 * 60

    @ObservationIgnored private let feed: UpdateCheck.Feed
    @ObservationIgnored private var periodicTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "dev.itaehyeok.CapsLockControl", category: "Update")

    init(feed: UpdateCheck.Feed = .github) {
        self.feed = feed
    }

    var currentVersion: String { UpdateCheck.currentVersion }

    func startPeriodicChecks() {
        guard periodicTask == nil else { return }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                // 연속 시계라 잠자기 동안에도 흐른다. 깨어나면 밀린 확인을 바로 한다.
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    /// 창을 열 때처럼 자주 불리는 자리에서 쓴다. 방금 물었으면 넘어간다.
    func checkIfDue() async {
        if let last = lastCheckedAt, Date().timeIntervalSince(last) < Self.minimumGap { return }
        await check()
    }

    func check() async {
        guard !isChecking, !isInstalling else { return }
        isChecking = true
        defer { isChecking = false }
        lastCheckedAt = Date()
        guard let release = await UpdateCheck.latest(feed: feed) else {
            lastResult = .failed
            return
        }
        if UpdateCheck.isNewer(release.version, than: currentVersion) {
            if available?.version != release.version {
                log.notice("새 버전 v\(release.version, privacy: .public) (지금 v\(self.currentVersion, privacy: .public))")
                installFailure = nil
            }
            available = release
            lastResult = .available
        } else {
            // 올렸던 릴리스를 내렸을 수도 있다. 그러면 안내도 거둔다.
            available = nil
            lastResult = .upToDate
        }
    }

    /// 받아서 확인한 뒤 앱을 끈다. 꺼진 뒤 스크립트가 바꿔 끼우고 새 버전을 연다.
    func install() {
        guard let release = available, !isInstalling else { return }
        isInstalling = true
        installFailure = nil
        Task {
            do {
                let prepared = try await AppUpdater.prepare(release)
                try AppUpdater.install(prepared)
                log.notice("v\(release.version, privacy: .public) 로 바꿔 끼우려고 앱을 끕니다")
                NSApp.terminate(nil)
            } catch {
                log.error("업데이트 실패 v\(release.version, privacy: .public): \(error.localizedDescription, privacy: .public)")
                installFailure = error.localizedDescription
                isInstalling = false
            }
        }
    }

    func openReleasePage() {
        guard let url = available?.pageURL else { return }
        NSWorkspace.shared.open(url)
    }
}
