import Foundation

/// 설정을 파일 하나로 주고받는다. GitHub 없이 백업하거나 다른 Mac 으로 옮길 때 쓴다.
///
/// 형식은 `shortcuts.json` 과 똑같다. 내보낸 파일을 설정 폴더에 그대로 넣어도 읽힌다.
enum ConfigFile {

    enum ReadError: LocalizedError, Equatable {
        case notConfiguration
        case newerVersion(found: Int, supported: Int)

        var errorDescription: String? {
            switch self {
            case .notConfiguration:
                "CapsLock Control 설정 파일이 아닙니다."
            case .newerVersion(let found, let supported):
                "더 새 버전의 앱에서 만든 파일입니다(파일 v\(found), 이 앱 v\(supported)). "
                + "앱을 업데이트한 뒤 가져오세요."
            }
        }
    }

    /// 저장 창에 미리 채워 둘 파일 이름. 날짜가 붙어 있으면 여러 번 내보내도 구별된다.
    static func suggestedName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "CapsLock Control 단축키 \(formatter.string(from: date)).json"
    }

    static func encode(_ config: CapsLockControlConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(config)
    }

    /// 가져올 파일을 읽는다.
    ///
    /// 설정은 빠진 키를 기본값으로 채워 읽기 때문에 아무 JSON 이나 `{}` 도 멀쩡한 빈 설정이
    /// 된다. 그대로 두면 엉뚱한 파일을 골랐을 때 단축키가 전부 "사라지는 항목" 으로 보이므로,
    /// 내보낸 파일이면 늘 있는 `layers` 가 없으면 설정 파일이 아니라고 본다.
    static func decode(_ data: Data) throws -> CapsLockControlConfig {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["layers"] is [String: Any],
              let config = try? JSONDecoder().decode(CapsLockControlConfig.self, from: data)
        else {
            throw ReadError.notConfiguration
        }
        guard config.version <= CapsLockControlConfig.currentVersion else {
            throw ReadError.newerVersion(found: config.version,
                                         supported: CapsLockControlConfig.currentVersion)
        }
        return config
    }
}
