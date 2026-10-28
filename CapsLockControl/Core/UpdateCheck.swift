import Foundation

/// 새 버전이 나왔는지 GitHub 릴리스에 묻는다.
///
/// 공개 저장소라 로그인 없이 묻는다. 로그인 없는 조회는 IP 하나당 시간당 60번까지인데,
/// 몇 시간에 한 번 묻는 이 앱에는 넉넉하다.
enum UpdateCheck {

    /// 릴리스를 어디서 묻고 어디서 받는가. 시험할 때만 다른 곳을 넣는다.
    struct Feed: Sendable {
        /// 최신 릴리스 하나를 돌려주는 주소(GitHub `…/releases/latest`).
        let latestAddress: String
        /// 받아도 되는 파일 주소의 앞부분. 릴리스 정보가 엉뚱한 곳을 가리키면 받지 않는다.
        let downloadPrefix: String

        /// `Tools/release.sh` 의 `RELEASE_REPO` 와 같은 저장소여야 한다.
        static let github = Feed(
            latestAddress: "https://api.github.com/repos/itaehyeok/capslock-control/releases/latest",
            downloadPrefix: "https://github.com/itaehyeok/capslock-control/releases/download/")
    }

    struct Release: Equatable, Sendable {
        /// `v` 를 뗀 버전. 늘 `0.1.0` 처럼 숫자 셋이다.
        let version: String
        /// 릴리스 페이지. 바뀐 내용을 보여 줄 때 연다.
        let pageURL: URL?
        /// 업데이트용 zip. 릴리스에 없거나 주소가 맞지 않으면 nil 이고, 그러면 설치하지 않는다.
        let assetURL: URL?
    }

    /// 릴리스에 올리는 업데이트용 zip 이름. `Tools/release.sh` 가 이 이름으로 올린다.
    static func assetName(version: String) -> String { "CapsLockControl-\(version).zip" }

    /// 지금 도는 앱의 버전(CFBundleShortVersionString).
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// 최신 릴리스. 못 받으면 nil — 조용히 넘어간다.
    /// 업데이트 확인은 거드는 기능이라, 실패했다고 경고를 띄우면 정작 봐야 할 경고를 가린다.
    static func latest(feed: Feed = .github, session: URLSession = .shared) async -> Release? {
        guard let url = URL(string: feed.latestAddress) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(data, feed: feed)
    }

    /// GitHub 릴리스 JSON 을 읽는다. 초안·시험판·버전 꼴이 아닌 태그는 없는 것으로 본다.
    static func parse(_ data: Data, feed: Feed = .github) -> Release? {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browserDownloadUrl: String
            }
            let tagName: String?
            let draft: Bool?
            let prerelease: Bool?
            let htmlUrl: String?
            let assets: [Asset]?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true,
              let tag = payload.tagName else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else { return nil }

        // 이름만 맞으면 받지 않는다. 이 저장소의 이 태그에 올린 파일이어야 한다.
        let name = assetName(version: version)
        let expected = feed.downloadPrefix + "\(tag)/\(name)"
        let assetURL = payload.assets?
            .first { $0.name == name && $0.browserDownloadUrl == expected }
            .flatMap { URL(string: $0.browserDownloadUrl) }
        return Release(version: version,
                       pageURL: payload.htmlUrl.flatMap(URL.init(string:)),
                       assetURL: assetURL)
    }

    /// `candidate` 가 `current` 보다 새로운가. 숫자 단위로 견준다 —
    /// 문자열로 견주면 "0.10.0" 이 "0.9.0" 보다 작다고 나온다.
    /// 자리 수가 달라도 빈 자리는 0 으로 본다("0.1" 과 "0.1.0" 은 같다).
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = numbers(candidate), b = numbers(current)
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func numbers(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}
