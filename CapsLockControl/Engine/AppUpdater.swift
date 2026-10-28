import Foundation

/// 받은 새 버전을 확인하고 지금 앱 자리에 바꿔 끼운다.
///
/// 도는 앱 번들은 건드리지 않는다. 검증한 새 앱을 지금 앱 옆에 숨김 이름으로 놓아 두고,
/// 따로 띄운 스크립트(UpdateHelperScript)가 앱이 꺼진 뒤에 바꿔 끼우고 다시 연다.
/// 옆에 두는 건 같은 디스크라야 `mv` 가 한 번에 끝나서다.
enum AppUpdater {

    struct Prepared: Sendable {
        /// 지금 앱 옆에 놓아 둔 새 앱.
        let stagedApp: URL
        /// 바꿔 끼울 자리(지금 앱).
        let installedApp: URL
    }

    enum Failure: LocalizedError {
        case noAsset
        case translocated
        case notWritable(String)
        case download
        case invalidArchive
        case wrongApp
        case wrongVersion
        case invalidSignature
        case wrongTeam
        case helper

        var errorDescription: String? {
            switch self {
            case .noAsset:
                "이 릴리스에 업데이트 파일이 없습니다. 릴리스 페이지에서 직접 받아 주세요."
            case .translocated:
                "다운로드 폴더 같은 임시 위치에서 실행 중이라 업데이트할 수 없습니다. "
                    + "앱을 응용 프로그램 폴더로 옮긴 뒤 다시 켜 주세요."
            case .notWritable(let folder):
                "\(folder) 폴더에 쓸 권한이 없어 업데이트하지 못했습니다."
            case .download:
                "업데이트 파일을 내려받지 못했습니다."
            case .invalidArchive:
                "업데이트 파일을 열 수 없습니다."
            case .wrongApp:
                "업데이트 파일에 든 앱이 CapsLock Control 이 아닙니다."
            case .wrongVersion:
                "업데이트 파일의 버전이 릴리스 정보와 다릅니다."
            case .invalidSignature:
                "업데이트 파일의 코드 서명을 확인할 수 없습니다."
            case .wrongTeam:
                "업데이트 파일의 서명 팀이 지금 앱과 다릅니다."
            case .helper:
                "앱을 바꿔 끼울 프로세스를 띄우지 못했습니다."
            }
        }
    }

    /// 바꿔 끼우는 스크립트가 남기는 로그. 앱이 꺼진 뒤의 일은 여기서만 볼 수 있다.
    static var logFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/CapsLockControl/update.log")
    }

    /// 내려받아 풀고 검증한 뒤 지금 앱 옆에 놓아 둔다. 여기까지는 지금 앱에 손대지 않는다.
    ///
    /// `installedApp` 은 시험할 때만 바꾼다. 평소에는 지금 도는 앱이다.
    static func prepare(
        _ release: UpdateCheck.Release,
        installedApp: URL = Bundle.main.bundleURL,
        session: URLSession = .shared
    ) async throws -> Prepared {
        guard let assetURL = release.assetURL else { throw Failure.noAsset }
        let installed = installedApp.resolvingSymlinksInPath()
        guard installed.pathExtension == "app" else { throw Failure.wrongApp }
        // 격리 속성이 붙은 채 다운로드 폴더에서 연 앱은 macOS 가 읽기 전용 임시 위치에서 돌린다.
        guard !installed.path.contains("/AppTranslocation/") else { throw Failure.translocated }
        let parent = installed.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw Failure.notWritable((parent.path as NSString).abbreviatingWithTildeInPath)
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapsLockControl-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let archive = work.appendingPathComponent("update.zip")
        do {
            let (downloaded, response) = try await session.download(from: assetURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.download }
            try FileManager.default.moveItem(at: downloaded, to: archive)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.download
        }
        let size = (try? archive.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0 && size < 200_000_000 else { throw Failure.download }

        // ditto 로 푼다. unzip 은 확장 속성을 잃어 서명이 깨질 수 있다.
        let unpacked = work.appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        guard run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path]) != nil else {
            throw Failure.invalidArchive
        }
        let candidate = unpacked.appendingPathComponent("CapsLockControl.app")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw Failure.invalidArchive }

        guard let candidateInfo = infoDictionary(of: candidate),
              let installedInfo = infoDictionary(of: installed),
              let identifier = installedInfo["CFBundleIdentifier"] as? String,
              candidateInfo["CFBundleIdentifier"] as? String == identifier else { throw Failure.wrongApp }
        guard candidateInfo["CFBundleShortVersionString"] as? String == release.version else {
            throw Failure.wrongVersion
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", candidate.path]) != nil else {
            throw Failure.invalidSignature
        }
        // 같은 팀이 서명한 앱만 받는다. 릴리스 정보가 바꿔치기돼도 남이 서명한 앱은 깔리지 않는다.
        // 손쉬운 사용 권한도 서명 팀이 같아야 업데이트 뒤에 그대로 남는다.
        guard let currentTeam = teamIdentifier(of: installed),
              let newTeam = teamIdentifier(of: candidate),
              currentTeam == newTeam else { throw Failure.wrongTeam }

        let staged = parent.appendingPathComponent(".CapsLockControl-update-\(UUID().uuidString).app")
        try FileManager.default.moveItem(at: candidate, to: staged)
        return Prepared(stagedApp: staged, installedApp: installed)
    }

    /// 바꿔 끼우는 스크립트를 띄운다. 부른 쪽은 곧바로 앱을 끈다 —
    /// 스크립트가 `waitingFor` 프로세스가 끝나기를 기다렸다가 바꿔 끼운다.
    ///
    /// `opener` 는 시험할 때만 바꾼다(새 앱을 실제로 띄우지 않게).
    static func install(
        _ prepared: Prepared,
        waitingFor pid: Int32 = ProcessInfo.processInfo.processIdentifier,
        opener: String? = nil
    ) throws {
        try? FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapsLockControl-update-\(UUID().uuidString).sh")
        do {
            try UpdateHelperScript.text().write(to: script, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path, prepared.stagedApp.path, prepared.installedApp.path,
                                 String(pid), logFile.path] + (opener.map { [$0] } ?? [])
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: script)
            try? FileManager.default.removeItem(at: prepared.stagedApp)
            throw Failure.helper
        }
    }

    // MARK: - 검사 도구

    /// `Bundle(url:)` 은 같은 경로를 한 번 읽으면 캐시해서, 바꿔 끼운 뒤에도 옛 값을 줄 수 있다.
    /// Info.plist 를 직접 읽는다.
    private static func infoDictionary(of app: URL) -> [String: Any]? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    private static func teamIdentifier(of app: URL) -> String? {
        guard let output = run("/usr/bin/codesign", ["-dvvv", app.path]) else { return nil }
        return output.split(separator: "\n")
            .first { $0.hasPrefix("TeamIdentifier=") }
            .map { String($0.dropFirst("TeamIdentifier=".count)) }
            .flatMap { $0 == "not set" ? nil : $0 }
    }

    /// 성공하면 출력(stdout+stderr), 실패하면 nil. `codesign -d` 는 정보를 stderr 로 낸다.
    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return nil }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: output, as: UTF8.self)
    }
}
