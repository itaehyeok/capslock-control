import Foundation
import os

enum GitSyncError: LocalizedError, Equatable {
    case notConfigured
    case gitMissing
    case commandFailed(command: String, output: String)
    case timedOut(command: String)
    case authenticationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "동기화할 저장소 주소가 설정되지 않았습니다."
        case .gitMissing:
            "git 을 찾을 수 없습니다. Xcode Command Line Tools 를 설치해 주세요."
        case .commandFailed(let command, let output):
            "git \(command) 실패\n\(output)"
        case .timedOut(let command):
            "git \(command) 가 응답하지 않아 중단했습니다. 네트워크를 확인해 주세요."
        case .authenticationFailed(let output):
            """
            GitHub 인증에 실패했습니다.

            • SSH 키가 ssh-agent 에 등록돼 있는지 확인해 주세요 (ssh-add -l).
            • GitHub 계정이 여러 개라면 기본 키가 다른 계정일 수 있습니다.             ~/.ssh/config 에 만들어 둔 Host 별칭을 주소에 쓰세요.
              예: git@github-personal:사용자/저장소.git
            • 어느 계정으로 인증되는지: ssh -T git@github.com

            \(output)
            """
        }
    }
}

/// 시스템 `git` 을 호출해 설정 파일을 GitHub 와 주고받는다.
///
/// 설계 원칙:
/// - **토큰·비밀번호·키를 앱에 저장하지 않는다.** 이미 설정된 SSH 인증을 그대로 쓴다.
/// - `git merge` 를 절대 쓰지 않는다. JSON 텍스트 병합은 충돌 표시를 파일에 박아
///   설정을 망가뜨린다. 병합은 `ConfigMerge` 가 항목 단위로 한다.
/// - clone 은 **버리는 작업 공간**이다. 매번 `reset --hard origin/<branch>` 로
///   맞춘 뒤 병합 결과만 커밋하므로, 중간에 죽어도 다음 실행이 깨끗하게 복구된다.
/// - 비밀번호 프롬프트로 멈추지 않게 `BatchMode` 와 타임아웃을 걸어 둔다.
actor GitSync {

    /// 저장소에 쌓인 export 하나.
    struct SnapshotRef: Identifiable, Sendable, Hashable {
        /// 저장소 안 경로. `snapshots/2026-09-11_153045_my-mbp.json`
        let path: String
        let date: Date?
        let hostName: String

        var id: String { path }

        var displayName: String {
            let when = date.map {
                $0.formatted(.dateTime.month().day().hour().minute())
            } ?? path
            return hostName.isEmpty ? when : "\(when) · \(hostName)"
        }
    }

    /// 저장소 루트의 "가장 최근" 사본. GitHub 웹에서 바로 읽어 보려고 둔다.
    static let latestFileName = "shortcuts.json"
    static let snapshotDirectoryName = "snapshots"

    private let log = Logger(subsystem: "dev.itaehyeok.CapsLockControl", category: "GitSync")
    private let remoteURL: String
    private let directory: URL
    private var branch = "main"

    init(remoteURL: String, directory: URL) {
        self.remoteURL = remoteURL
        self.directory = directory
    }

    private var latestFileURL: URL { directory.appendingPathComponent(Self.latestFileName) }
    private var snapshotDirectoryURL: URL {
        directory.appendingPathComponent(Self.snapshotDirectoryName, isDirectory: true)
    }

    /// git 이 따옴표로 감싼 경로를 원래대로 되돌린다.
    ///
    /// `core.quotepath=false` 로 대부분 막히지만, 따옴표나 제어문자가 든 경로는
    /// 설정과 무관하게 감싸져 나온다. 출력 형식을 한 군데서 정규화해 둔다.
    nonisolated static func unquotePath(_ raw: String) -> String {
        guard raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") else { return raw }
        let characters = Array(raw.dropFirst().dropLast())
        var bytes: [UInt8] = []
        var index = 0
        while index < characters.count {
            guard characters[index] == "\\", index + 1 < characters.count else {
                bytes.append(contentsOf: Array(String(characters[index]).utf8))
                index += 1
                continue
            }
            let next = characters[index + 1]
            // \354 처럼 8진수 세 자리가 오면 바이트 하나다.
            if next.isNumber, index + 3 < characters.count,
               let value = UInt8(String(characters[(index + 1)...(index + 3)]), radix: 8) {
                bytes.append(value)
                index += 4
                continue
            }
            switch next {
            case "n": bytes.append(0x0A)
            case "t": bytes.append(0x09)
            case "r": bytes.append(0x0D)
            case "\\": bytes.append(0x5C)
            case "\"": bytes.append(0x22)
            default: bytes.append(contentsOf: Array(String(next).utf8))
            }
            index += 2
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// 정렬 가능하고 사람이 읽을 수 있는 파일명. 콜론과 공백은 쓰지 않는다.
    private static let snapshotDateFormat = "yyyy-MM-dd_HHmmss"

    private static func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = snapshotDateFormat
        return formatter
    }

    /// Mac 이름을 파일명에 쓸 수 있게 다듬는다.
    ///
    /// **ASCII 만 남긴다.** `CharacterSet.alphanumerics` 는 한글도 통과시키는데,
    /// 그러면 `user의-MacBook-Pro.json` 같은 이름이 만들어지고 git 이 그 경로를
    /// 따옴표로 감싸 내놓는 설정(기본값)에서 목록 파싱이 깨진다.
    private static func sanitize(_ name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        let mapped = name.map { allowed.contains($0) ? $0 : "-" }
        let collapsed = String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "mac" : collapsed
    }

    // MARK: - 준비

    /// clone 이 없으면 만들고, 있으면 remote 주소를 맞춘다.
    func prepare() async throws {
        guard !remoteURL.isEmpty else { throw GitSyncError.notConfigured }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else {
            throw GitSyncError.gitMissing
        }

        let gitDirectory = directory.appendingPathComponent(".git")
        if !FileManager.default.fileExists(atPath: gitDirectory.path) {
            // 중간에 실패한 clone 이 남아 있을 수 있다.
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(
                at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try await run(["clone", "--quiet", remoteURL, directory.path],
                              inRepository: false, timeout: 60)
            log.info("저장소를 복제했습니다")
        } else {
            _ = try? await run(["remote", "set-url", "origin", remoteURL])
        }
        branch = await resolveBranch()
    }

    /// 어떤 브랜치를 볼지 정한다.
    ///
    /// 로컬 HEAD 만 보면 안 된다. 원격 HEAD 가 없는 저장소를 clone 하면 git 이
    /// `init.defaultBranch`(보통 master)로 로컬 HEAD 를 만들어 버려서, 정작 내용이
    /// 들어 있는 `origin/main` 을 놓친다. 원격이 알려 주는 값 → 실제로 존재하는
    /// 흔한 이름 → 로컬 HEAD 순으로 찾는다.
    private func resolveBranch() async -> String {
        // 1) clone 이 기록해 둔 원격의 기본 브랜치.
        if let reference = try? await run(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"]) {
            let name = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            if let slash = name.lastIndex(of: "/") {
                let branch = String(name[name.index(after: slash)...])
                if !branch.isEmpty { return branch }
            }
        }
        // 2) 실제로 있는 브랜치를 확인한다.
        for candidate in ["main", "master"] where await revisionExists("origin/\(candidate)") {
            return candidate
        }
        // 3) 커밋이 하나도 없는 저장소. 로컬 HEAD 가 첫 push 로 만들어질 이름이다.
        let local = (try? await run(["symbolic-ref", "--short", "HEAD"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return local.isEmpty ? "main" : local
    }

    private func revisionExists(_ revision: String) async -> Bool {
        (try? await run(["rev-parse", "--verify", "--quiet", revision])) != nil
    }

    // MARK: - 읽기

    /// 원격을 받아 와서 쌓여 있는 export 목록을 읽는다. 로컬 설정은 건드리지 않는다.
    func listSnapshots() async throws -> [SnapshotRef] {
        _ = try await run(["fetch", "--quiet", "origin"], timeout: 45)
        // 처음 clone 했을 때는 비어 있던 저장소가 그 사이 채워졌을 수 있다.
        branch = await resolveBranch()
        guard await revisionExists("origin/\(branch)") else { return [] }
        // 실패를 빈 목록으로 삼키면 "스냅샷이 없다" 와 구분이 안 된다.
        let output = try await run([
            "ls-tree", "-r", "--name-only", "origin/\(branch)",
            "--", Self.snapshotDirectoryName,
        ])

        let formatter = Self.makeFormatter()
        return output
            .split(separator: "\n")
            .map { Self.unquotePath(String($0)) }
            .filter { $0.hasSuffix(".json") }
            .map { path -> SnapshotRef in
                // snapshots/2026-09-11_153045_my-mbp.json
                let stem = (path as NSString).lastPathComponent
                    .replacingOccurrences(of: ".json", with: "")
                let parts = stem.split(separator: "_", maxSplits: 2).map(String.init)
                let date = parts.count >= 2
                    ? formatter.date(from: "\(parts[0])_\(parts[1])") : nil
                let host = parts.count >= 3 ? parts[2] : ""
                return SnapshotRef(path: path, date: date, hostName: host)
            }
            // 최신이 위로. 파일명 형식이 깨진 것은 뒤로 보낸다.
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    func loadSnapshot(_ reference: SnapshotRef) async throws -> CapsLockControlConfig {
        let output = try await run(["show", "origin/\(branch):\(reference.path)"])
        guard let data = output.data(using: .utf8) else {
            throw GitSyncError.commandFailed(command: "show", output: "스냅샷을 읽지 못했습니다.")
        }
        return try JSONDecoder().decode(CapsLockControlConfig.self, from: data)
    }

    // MARK: - 쓰기

    /// 지금 설정을 **새 스냅샷으로** 올린다. 기존 스냅샷은 지우지 않는다.
    ///
    /// `reset --hard origin/<branch>` + `clean` 으로 시작하므로 우리 커밋은 항상
    /// 원격의 자손이고, 앞선 실패가 남긴 찌꺼기도 함께 정리된다.
    /// 그래서 push 가 거부되거나 merge commit 이 생기는 일이 없다.
    @discardableResult
    func export(_ config: CapsLockControlConfig) async throws -> SnapshotRef {
        _ = try? await run(["fetch", "--quiet", "origin"], timeout: 45)
        branch = await resolveBranch()
        // 원격 브랜치가 있으면 그 위에 쌓는다. 커밋이 하나도 없는 새 저장소면
        // 이 커밋이 첫 커밋이 되므로 reset 할 대상이 없다.
        if await revisionExists("origin/\(branch)") {
            _ = try await run(["reset", "--hard", "--quiet", "origin/\(branch)"])
            _ = try? await run(["clean", "-fd", "--quiet"])
        }

        let now = Date()
        let host = Self.sanitize(Host.current().localizedName ?? "mac")
        let stem = "\(Self.makeFormatter().string(from: now))_\(host)"
        let relativePath = "\(Self.snapshotDirectoryName)/\(stem).json"

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(config)

        try FileManager.default.createDirectory(
            at: snapshotDirectoryURL, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(relativePath), options: [.atomic])
        // 루트 사본도 갱신해 둔다. GitHub 웹에서 현재 설정을 바로 읽을 수 있다.
        try data.write(to: latestFileURL, options: [.atomic])

        _ = try await run(["add", "--", Self.latestFileName, relativePath])
        let identity = try await commitIdentityArguments()
        _ = try await run(identity + ["commit", "--quiet", "-m", "Export \(stem)"])
        _ = try await run(["push", "--quiet", "origin", "HEAD:\(branch)"], timeout: 45)

        log.info("export 완료 \(relativePath, privacy: .public)")
        return SnapshotRef(path: relativePath, date: now, hostName: host)
    }

    /// 전역 git 설정이 없는 Mac 에서도 커밋이 실패하지 않게 한다.
    private func commitIdentityArguments() async throws -> [String] {
        let name = (try? await run(["config", "--get", "user.name"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let email = (try? await run(["config", "--get", "user.email"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var arguments: [String] = []
        if name.isEmpty { arguments += ["-c", "user.name=CapsLockControl"] }
        if email.isEmpty { arguments += ["-c", "user.email=capslockcontrol@localhost"] }
        return arguments
    }

    // MARK: - git 실행

    private func run(
        _ arguments: [String],
        inRepository: Bool = true,
        timeout: TimeInterval = 20
    ) async throws -> String {
        let fullArguments = inRepository ? ["-C", directory.path] + arguments : arguments
        let label = arguments.first ?? "git"
        let output = try await Task.detached(priority: .userInitiated) {
            try Self.execute(fullArguments, timeout: timeout, label: label)
        }.value
        return output
    }

    private struct CommandOutput: Sendable {
        let status: Int32
        let standardOutput: String
        let standardError: String
    }

    /// Process 는 Sendable 이 아니므로 이 함수 안에서만 다룬다.
    private nonisolated static func execute(
        _ arguments: [String],
        timeout: TimeInterval,
        label: String
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // core.quotepath 가 켜져 있으면(기본값) 경로에 ASCII 가 아닌 글자가 있을 때
        // git 이 따옴표로 감싸고 8진 이스케이프해서 내놓는다. 사용자 설정에 따라
        // 출력이 달라지면 안 되므로 항상 끄고 부른다.
        process.arguments = ["-c", "core.quotepath=false"] + arguments

        var environment = ProcessInfo.processInfo.environment
        // 비밀번호·통과구문 프롬프트로 멈추지 않게 한다. 멈추면 UI 가 영원히 기다린다.
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_ASKPASS"] = "/usr/bin/false"
        environment["SSH_ASKPASS"] = "/usr/bin/false"
        environment["DISPLAY"] = ""
        environment["GIT_SSH_COMMAND"] =
            "ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw GitSyncError.commandFailed(command: label, output: error.localizedDescription)
        }

        // 파이프를 먼저 비워야 출력이 커도 막히지 않는다.
        let group = DispatchGroup()
        var outData = Data()
        var errData = Data()
        group.enter()
        DispatchQueue.global().async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            usleep(300_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            _ = group.wait(timeout: .now() + 2)
            throw GitSyncError.timedOut(command: label)
        }
        _ = group.wait(timeout: .now() + 5)

        let standardOutput = String(decoding: outData, as: UTF8.self)
        let standardError = String(decoding: errData, as: UTF8.self)

        guard process.terminationStatus == 0 else {
            let combined = (standardError + standardOutput).trimmingCharacters(in: .whitespacesAndNewlines)
            if combined.contains("Permission denied")
                || combined.contains("Could not read from remote repository")
                || combined.contains("Host key verification failed") {
                throw GitSyncError.authenticationFailed(combined)
            }
            throw GitSyncError.commandFailed(command: label, output: combined)
        }
        return standardOutput
    }
}
