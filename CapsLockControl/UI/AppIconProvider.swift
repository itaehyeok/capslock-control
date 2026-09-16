import AppKit

/// 앱 아이콘 캐시.
///
/// `NSWorkspace.icon(forFile:)` 는 디스크를 건드리는 조회다.
/// 키캡이 40개씩 그려지는 뷰 본문에서 매번 부르면 스크롤이 끊긴다.
@MainActor
final class AppIconProvider {
    static let shared = AppIconProvider()

    private var cache: [String: NSImage?] = [:]

    private init() {}

    func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage? {
        if let cached = cache[bundleIdentifier] { return cached }
        let image = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[bundleIdentifier] = image
        return image
    }

    /// 앱을 설치/삭제했을 수 있을 때. 설정을 다시 읽을 때 함께 부른다.
    func invalidate() {
        cache.removeAll()
    }
}
