import AppKit
import Observation

/// 단축키에 걸 수 있는 앱 목록.
///
/// 1순위는 **실행 중인 앱**이다(요구사항 §10). 다만 실행 중인 앱만 보여 주면
/// 지금 안 켜져 있는 앱에는 단축키를 걸 수 없다. 그래서 설치된 앱 목록을
/// 두 번째 섹션으로 함께 보여 준다.
@MainActor
@Observable
final class ApplicationCatalog {

    static let shared = ApplicationCatalog()

    struct Entry: Identifiable, Hashable, Sendable {
        let bundleIdentifier: String
        let name: String
        let bundleURLPath: String?

        var id: String { bundleIdentifier }
    }

    private(set) var running: [Entry] = []
    private(set) var installed: [Entry] = []
    private(set) var isLoadingInstalled = false

    private init() {
        refreshRunning()
        observeWorkspace()
    }

    // MARK: - 실행 중인 앱

    /// Dock 에 뜨는 평범한 앱만 남긴다.
    /// 메뉴바 전용 앱이나 백그라운드 프로세스까지 보여 주면 목록이 쓸모없어진다.
    func refreshRunning() {
        var seen: Set<String> = []
        running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> Entry? in
                guard let bundleIdentifier = app.bundleIdentifier,
                      seen.insert(bundleIdentifier).inserted else { return nil }
                return Entry(
                    bundleIdentifier: bundleIdentifier,
                    name: app.localizedName ?? bundleIdentifier,
                    bundleURLPath: app.bundleURL?.path
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            // Notification 자체는 건드리지 않는다(Sendable 이 아니다). 다시 훑기만 한다.
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshRunning() }
            }
        }
    }

    // MARK: - 설치된 앱

    /// 처음 피커를 열 때 한 번만 훑는다. 디스크를 200번쯤 건드리므로 메인 스레드 밖에서.
    func loadInstalledIfNeeded() {
        guard installed.isEmpty, !isLoadingInstalled else { return }
        isLoadingInstalled = true
        Task {
            let entries = await Self.scanInstalledApplications()
            self.installed = entries
            self.isLoadingInstalled = false
        }
    }

    private static func scanInstalledApplications() async -> [Entry] {
        await Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            var found: [String: Entry] = [:]

            func inspect(_ url: URL) {
                guard url.pathExtension == "app",
                      let bundle = Bundle(url: url),
                      let bundleIdentifier = bundle.bundleIdentifier,
                      found[bundleIdentifier] == nil else { return }
                found[bundleIdentifier] = Entry(
                    bundleIdentifier: bundleIdentifier,
                    name: url.deletingPathExtension().lastPathComponent,
                    bundleURLPath: url.path
                )
            }

            for path in applicationSearchDirectories {
                let directory = URL(fileURLWithPath: path)
                guard let contents = try? manager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]) else { continue }
                for url in contents {
                    if url.pathExtension == "app" {
                        inspect(url)
                    } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                        // /Applications/Utilities 처럼 한 단계 들어간 폴더까지만 본다.
                        let nested = (try? manager.contentsOfDirectory(
                            at: url, includingPropertiesForKeys: nil,
                            options: [.skipsHiddenFiles])) ?? []
                        for child in nested { inspect(child) }
                    }
                }
            }

            return found.values
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }.value
    }

    // MARK: - 검색

    /// localizedName 과 bundleIdentifier 를 대소문자 구분 없이 부분 일치로 찾는다.
    /// 타자 한 글자마다 호출된다.
    func search(_ query: String) -> (running: [Entry], installed: [Entry]) {
        Self.filter(running: running, installed: installed, query: query)
    }

    /// 검색의 실제 규칙. NSWorkspace 에 의존하지 않아 테스트할 수 있다.
    ///
    /// - 실행 중인 앱에 이미 있는 것은 "설치됨" 섹션에서 빼서 중복을 없앤다.
    /// - 검색어가 비어 있으면 전부 보여 준다.
    nonisolated static func filter(
        running: [Entry],
        installed: [Entry],
        query: String
    ) -> (running: [Entry], installed: [Entry]) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let runningIDs = Set(running.map(\.bundleIdentifier))
        let installedPool = installed.filter { !runningIDs.contains($0.bundleIdentifier) }
        guard !trimmed.isEmpty else { return (running, installedPool) }
        return (running.filter { $0.matches(trimmed) },
                installedPool.filter { $0.matches(trimmed) })
    }
}

extension ApplicationCatalog.Entry {
    nonisolated func matches(_ query: String) -> Bool {
        name.localizedCaseInsensitiveContains(query)
            || bundleIdentifier.localizedCaseInsensitiveContains(query)
    }
}


/// 설치된 앱을 찾을 폴더. MainActor 밖(백그라운드 훑기)에서도 읽으므로
/// 클래스 안의 static 이 아니라 파일 전역에 둔다.
private let applicationSearchDirectories: [String] = [
    "/Applications",
    "/System/Applications",
    "/System/Applications/Utilities",
    "/Applications/Xcode.app/Contents/Developer/Applications",
    NSHomeDirectory() + "/Applications",
]
