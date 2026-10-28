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
