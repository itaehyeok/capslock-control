import Foundation
import Testing
@testable import CapsLockControl

@Suite("설정 파일 내보내기")
struct ConfigFileTests {

    private var sample: CapsLockControlConfig {
        var config = CapsLockControlConfig()
        config.setAction(.application(ApplicationTarget(bundleIdentifier: "com.apple.Safari",
                                                        displayName: "Safari")),
                         layer: .capsLock, keyIdentifier: "s")
        config.defaults.layerTapTimeoutMilliseconds = 300
        return config
    }

    @Test("내보낸 파일은 설정 파일과 같은 형식이라 그대로 다시 읽힌다")
    func exportedFileRoundTrips() throws {
        let data = try ConfigFile.encode(sample)
        let decoded = try JSONDecoder().decode(CapsLockControlConfig.self, from: data)
        #expect(decoded == sample)
    }

    @Test("파일 이름에 날짜가 붙는다")
    func suggestedNameHasDate() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 28
        components.hour = 12
        let date = try #require(Calendar.current.date(from: components))
        #expect(ConfigFile.suggestedName(for: date) == "CapsLock Control 단축키 2026-10-28.json")
    }
}

@Suite("설정 파일 가져오기")
struct ConfigFileReadTests {

    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test("내보낸 파일은 그대로 읽힌다")
    func readsExportedFile() throws {
        var config = CapsLockControlConfig()
        config.setAction(.application(ApplicationTarget(bundleIdentifier: "com.apple.Safari",
                                                        displayName: "Safari")),
                         layer: .capsLock, keyIdentifier: "s")
        #expect(try ConfigFile.decode(ConfigFile.encode(config)) == config)
    }

    @Test("손으로 만든 파일은 layers 만 있어도 읽힌다")
    func readsMinimalFile() throws {
        let config = try ConfigFile.decode(data(#"{"layers": {}}"#))
        #expect(config.layers.isEmpty)
    }

    @Test("설정 파일이 아니면 빈 설정으로 읽지 않는다",
          arguments: ["{}", #"{"name": "package"}"#, "[1, 2]", "not json", #"{"layers": []}"#])
    func rejectsOtherFiles(_ json: String) {
        #expect(throws: ConfigFile.ReadError.notConfiguration) {
            try ConfigFile.decode(data(json))
        }
    }

    @Test("더 새 버전에서 만든 파일은 가져오지 않는다")
    func rejectsNewerVersion() {
        let newer = CapsLockControlConfig.currentVersion + 1
        #expect(throws: ConfigFile.ReadError.newerVersion(
            found: newer, supported: CapsLockControlConfig.currentVersion)) {
            try ConfigFile.decode(data(#"{"version": \#(newer), "layers": {}}"#))
        }
    }
}
