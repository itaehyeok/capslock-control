import Foundation
import Testing
@testable import CapsLockControl

@Suite("새 버전 확인")
struct UpdateCheckTests {

    /// GitHub `releases/latest` 응답에서 쓰는 칸만 남긴 것.
    private func payload(
        tag: String = "v0.2.0",
        draft: Bool = false,
        prerelease: Bool = false,
        assetName: String? = nil,
        assetURL: String? = nil
    ) -> Data {
        let name = assetName ?? "CapsLockControl-\(tag.dropFirst()).zip"
        let url = assetURL
            ?? "https://github.com/itaehyeok/capslock-control/releases/download/\(tag)/\(name)"
        let json = """
        {"tag_name":"\(tag)","draft":\(draft),"prerelease":\(prerelease),
         "html_url":"https://github.com/itaehyeok/capslock-control/releases/tag/\(tag)",
         "assets":[
           {"name":"CapsLockControl-\(tag.dropFirst()).dmg","browser_download_url":"https://github.com/itaehyeok/capslock-control/releases/download/\(tag)/CapsLockControl-\(tag.dropFirst()).dmg"},
           {"name":"\(name)","browser_download_url":"\(url)"}]}
        """
        return Data(json.utf8)
    }

    @Test("정식 릴리스에서 버전과 업데이트 파일을 읽는다")
    func parsesRelease() throws {
        let release = try #require(UpdateCheck.parse(payload()))
        #expect(release.version == "0.2.0")
        #expect(release.assetURL?.absoluteString
                == "https://github.com/itaehyeok/capslock-control/releases/download/v0.2.0/CapsLockControl-0.2.0.zip")
        #expect(release.pageURL?.absoluteString
                == "https://github.com/itaehyeok/capslock-control/releases/tag/v0.2.0")
    }

    @Test("초안과 시험판은 없는 것으로 본다")
    func ignoresDraftAndPrerelease() {
        #expect(UpdateCheck.parse(payload(draft: true)) == nil)
        #expect(UpdateCheck.parse(payload(prerelease: true)) == nil)
    }

    @Test("숫자 셋이 아닌 태그는 없는 것으로 본다")
    func ignoresOddTags() {
        #expect(UpdateCheck.parse(payload(tag: "v0.2")) == nil)
        #expect(UpdateCheck.parse(payload(tag: "nightly")) == nil)
    }

    /// 릴리스 정보가 바꿔치기돼도 다른 곳의 파일은 받지 않는다.
    @Test("다른 저장소·다른 태그의 파일은 받지 않는다")
    func rejectsForeignAsset() throws {
        let foreign = try #require(UpdateCheck.parse(payload(
            assetURL: "https://github.com/someone/else/releases/download/v0.2.0/CapsLockControl-0.2.0.zip")))
        #expect(foreign.assetURL == nil)
        let otherTag = try #require(UpdateCheck.parse(payload(
            assetURL: "https://github.com/itaehyeok/capslock-control/releases/download/v0.1.0/CapsLockControl-0.2.0.zip")))
        #expect(otherTag.assetURL == nil)
    }

    @Test("버전은 숫자로 견준다")
    func comparesNumerically() {
        #expect(UpdateCheck.isNewer("0.10.0", than: "0.9.0"))
        #expect(UpdateCheck.isNewer("0.1.1", than: "0.1.0"))
        #expect(UpdateCheck.isNewer("1.0.0", than: "0.99.99"))
        #expect(!UpdateCheck.isNewer("0.1.0", than: "0.1.0"))
        #expect(!UpdateCheck.isNewer("0.1.0", than: "0.2.0"))
        // 개발 빌드의 "0.1" 은 "0.1.0" 과 같다.
        #expect(!UpdateCheck.isNewer("0.1.0", than: "0.1"))
    }
}

/// 주소마다 정해 둔 응답을 돌려주는 가짜 네트워크. 3xx 는 Location 으로 따라가게 한다.
private final class StubProtocol: URLProtocol {
    struct Route {
        var status: Int
        var location: String?
        var body = Data()
    }

    private static let lock = NSLock()
    /// `lock` 안에서만 읽고 쓴다.
    nonisolated(unsafe) private static var routes: [String: Route] = [:]

    static func set(_ address: String, _ route: Route) {
        lock.withLock { routes[address] = route }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let route = Self.lock.withLock { Self.routes[url.absoluteString] } ?? Route(status: 404)
        let headers = route.location.map { ["Location": $0] } ?? [:]
        guard let response = HTTPURLResponse(url: url, statusCode: route.status,
                                             httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        if (300..<400).contains(route.status), let location = route.location.flatMap(URL.init(string:)) {
            var next = URLRequest(url: location)
            next.httpMethod = request.httpMethod
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: route.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// API 가 막혀도(로그인 없는 조회 한도) 웹 주소로 새 버전을 찾는다.
@Suite("API 가 막혔을 때 새 버전 확인")
struct UpdateCheckWebFallbackTests {

    /// 시험마다 저장소 이름을 달리해 가짜 응답이 서로 섞이지 않게 한다.
    private let repo = "https://example.test/\(UUID().uuidString)"
    private var feed: UpdateCheck.Feed {
        UpdateCheck.Feed(latestAddress: "\(repo)/api/latest",
                         webLatestAddress: "\(repo)/releases/latest",
                         tagPagePrefix: "\(repo)/releases/tag/",
                         downloadPrefix: "\(repo)/releases/download/")
    }
    private var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }
    private var zipAddress: String { "\(repo)/releases/download/v9.9.9/CapsLockControl-9.9.9.zip" }

    private func blockAPIAndPointWebAt(_ tagPage: String) {
        StubProtocol.set("\(repo)/api/latest", .init(status: 403))
        StubProtocol.set("\(repo)/releases/latest", .init(status: 302, location: tagPage))
        StubProtocol.set(tagPage, .init(status: 200))
    }

    @Test("태그 페이지 주소에서 버전과 zip 주소를 만든다")
    func readsTagPage() throws {
        let page = try #require(URL(string: "https://github.com/itaehyeok/capslock-control/releases/tag/v0.3.0"))
        let release = try #require(UpdateCheck.release(fromTagPage: page))
        #expect(release.version == "0.3.0")
        #expect(release.pageURL == page)
        #expect(release.assetURL?.absoluteString
                == "https://github.com/itaehyeok/capslock-control/releases/download/v0.3.0/CapsLockControl-0.3.0.zip")
    }

    @Test("다른 저장소나 버전 꼴이 아닌 태그로 넘어가면 믿지 않는다",
          arguments: ["https://github.com/someone/else/releases/tag/v0.3.0",
                      "https://github.com/itaehyeok/capslock-control/releases",
                      "https://github.com/itaehyeok/capslock-control/releases/tag/nightly"])
    func rejectsOtherPages(_ address: String) throws {
        #expect(UpdateCheck.release(fromTagPage: try #require(URL(string: address))) == nil)
    }

    @Test("API 가 403 이면 웹 주소로 찾는다")
    func fallsBackToWeb() async throws {
        blockAPIAndPointWebAt("\(repo)/releases/tag/v9.9.9")
        StubProtocol.set(zipAddress, .init(status: 200))
        let release = try #require(await UpdateCheck.latest(feed: feed, session: session))
        #expect(release.version == "9.9.9")
        #expect(release.assetURL?.absoluteString == zipAddress)
    }

    @Test("웹 주소로 찾았는데 zip 이 없으면 설치하지 않는다")
    func missingZipIsNotInstallable() async throws {
        blockAPIAndPointWebAt("\(repo)/releases/tag/v9.9.9")
        let release = try #require(await UpdateCheck.latest(feed: feed, session: session))
        #expect(release.version == "9.9.9")
        #expect(release.assetURL == nil)
    }

    @Test("API 가 답하면 웹 주소는 묻지 않는다")
    func prefersAPI() async throws {
        let json = #"{"tag_name":"v1.2.3","draft":false,"prerelease":false,"assets":[]}"#
        // 웹 주소도 답할 수 있게 해 두고, API 가 답하면 그쪽을 쓰는지 본다.
        blockAPIAndPointWebAt("\(repo)/releases/tag/v9.9.9")
        StubProtocol.set("\(repo)/api/latest", .init(status: 200, body: Data(json.utf8)))
        let release = try #require(await UpdateCheck.latest(feed: feed, session: session))
        #expect(release.version == "1.2.3")
    }

    @Test("둘 다 안 되면 조용히 넘어간다")
    func bothFail() async {
        StubProtocol.set("\(repo)/api/latest", .init(status: 403))
        StubProtocol.set("\(repo)/releases/latest", .init(status: 429))
        #expect(await UpdateCheck.latest(feed: feed, session: session) == nil)
    }
}

@Suite("앱 바꿔 끼우기 스크립트")
struct UpdateHelperScriptTests {

    /// 가짜 앱 폴더 둘을 만들고 스크립트를 돌린다. 기다릴 PID 는 이미 끝난 프로세스다.
    private func run(opener: String) throws -> (directory: URL, status: Int32, log: String) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpdateHelperScriptTests-\(UUID().uuidString)")
        let target = directory.appendingPathComponent("CapsLockControl.app")
        let stage = directory.appendingPathComponent(".CapsLockControl-update.app")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        try "old".write(to: target.appendingPathComponent("version"), atomically: true, encoding: .utf8)
        try "new".write(to: stage.appendingPathComponent("version"), atomically: true, encoding: .utf8)

        let finished = Process()
        finished.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try finished.run()
        finished.waitUntilExit()

        let script = directory.appendingPathComponent("helper.sh")
        let log = directory.appendingPathComponent("update.log")
        try UpdateHelperScript.text(waitSeconds: 1).write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, stage.path, target.path,
                             String(finished.processIdentifier), log.path, opener]
        try process.run()
        process.waitUntilExit()
        let logText = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return (directory, process.terminationStatus, logText)
    }

    private func contents(_ directory: URL) throws -> (version: String, leftovers: [String]) {
        let version = try String(contentsOf: directory.appendingPathComponent("CapsLockControl.app/version"),
                                 encoding: .utf8)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".app") && $0 != "CapsLockControl.app" }
        return (version, leftovers)
    }

    @Test("새 앱을 놓고 연다")
    func replacesAndOpens() throws {
        let result = try run(opener: "/usr/bin/true")
        defer { try? FileManager.default.removeItem(at: result.directory) }
        #expect(result.status == 0)
        let after = try contents(result.directory)
        #expect(after.version == "new")
        // 백업과 놓아 둔 새 앱이 남지 않는다.
        #expect(after.leftovers.isEmpty)
        #expect(result.log.contains("교체 완료"))
    }

    /// 새 앱이 안 열리면 원래 앱으로 되돌린다. 키보드 앱이 통째로 사라지면 곤란하다.
    @Test("새 앱을 못 열면 있던 앱으로 되돌린다")
    func rollsBackWhenOpenFails() throws {
        let result = try run(opener: "/usr/bin/false")
        defer { try? FileManager.default.removeItem(at: result.directory) }
        #expect(result.status != 0)
        let after = try contents(result.directory)
        #expect(after.version == "old")
        #expect(after.leftovers.isEmpty)
        #expect(result.log.contains("되돌림"))
    }
}
