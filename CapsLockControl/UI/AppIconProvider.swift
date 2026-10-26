import AppKit
import CoreServices
import Observation

/// 앱 아이콘 캐시.
///
/// `NSWorkspace.icon(forFile:)` 는 디스크를 건드리는 조회다.
/// 키캡이 40개씩 그려지는 뷰 본문에서 매번 부르면 스크롤이 끊긴다.
@MainActor
@Observable
final class AppIconProvider {
    static let shared = AppIconProvider()

    @ObservationIgnored private var cache: [String: NSImage?] = [:]
    /// LaunchServices 는 모르지만 디스크에 남아 있는 앱 사본(다른 Xcode 안의 Simulator 처럼).
    /// 번들 ID 로 실행은 안 돼서 Missing 이지만 아이콘은 여기서 빌려 온다.
    /// 뷰가 읽는 값이라, 찾기가 끝나면 그 키가 다시 그려진다.
    private var strayCopies: [String: URL] = [:]
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    private init() {}

    func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage? {
        // 캐시에 있어도 먼저 읽어 둔다. 그래야 사본을 찾았을 때 이 뷰가 다시 그려진다.
        let strayCopy = strayCopies[bundleIdentifier]
        if let cached = cache[bundleIdentifier] { return cached }
        let image = (NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) ?? strayCopy)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[bundleIdentifier] = image
        return image
    }

    /// 앱을 설치/삭제했을 수 있을 때. 설정을 다시 읽을 때 함께 부른다.
    /// 설치돼 있지 않은 앱은 디스크에 남은 사본을 백그라운드에서 다시 찾는다.
    func invalidate(missingBundleIdentifiers: Set<String>) {
        cache.removeAll()
        searchTask?.cancel()
        searchTask = Task {
            let found = await Self.locateStrayCopies(of: missingBundleIdentifiers)
            guard !Task.isCancelled, found != strayCopies else { return }
            for (identifier, url) in found where strayCopies[identifier] != url {
                cache.removeValue(forKey: identifier)
            }
            strayCopies = found
        }
    }

    /// Spotlight 동기 조회는 런루프를 돌린다. 뷰 본문에서 부르면 SwiftUI 갱신이 꼬여서
    /// 그 키캡이 선택돼도 파랗게 바뀌지 않았다(실측). 그래서 메인 밖에서만 부른다.
    private nonisolated static func locateStrayCopies(of bundleIdentifiers: Set<String>) async -> [String: URL] {
        guard !bundleIdentifiers.isEmpty else { return [:] }
        return await Task.detached(priority: .utility) {
            var found: [String: URL] = [:]
            for identifier in bundleIdentifiers {
                if let url = spotlightURL(forBundleIdentifier: identifier) { found[identifier] = url }
            }
            return found
        }.value
    }

    private nonisolated static func spotlightURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        // 설정 파일에서 온 문자열이다. 쿼리 문법을 깨는 글자가 있으면 찾지 않는다.
        guard !bundleIdentifier.isEmpty,
              !bundleIdentifier.contains(where: { "'\"\\*".contains($0) }),
              let query = MDQueryCreate(kCFAllocatorDefault,
                                        "kMDItemCFBundleIdentifier == '\(bundleIdentifier)'" as CFString,
                                        nil, nil),
              MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue))
        else { return nil }
        for index in 0..<MDQueryGetResultCount(query) {
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            if let path = MDItemCopyAttribute(item, kMDItemPath) as? String {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}
