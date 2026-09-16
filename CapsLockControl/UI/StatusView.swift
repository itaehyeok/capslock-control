import SwiftUI

/// 엔진·매핑·설정 파일 상태와 실시간 로그.
/// 단축키 목록은 Key Layout 탭이 담당한다.
struct StatusView: View {
    let model: EngineModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                mappingCard
                configCard
                logCard
            }
            .padding(20)
        }
    }

    private var mappingCard: some View {
        card(title: "HID 키 매핑", tint: model.isHIDMappingApplied ? .green : .secondary) {
            ForEach(model.hidMappings) { mapping in
                HStack(spacing: 8) {
                    Image(systemName: model.isHIDMappingApplied ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(model.isHIDMappingApplied ? .green : .secondary)
                    Text(mapping.label).font(.callout).monospaced()
                }
            }
            Divider()
            Text("이 매핑은 앱이 켜져 있는 동안에만 유지되고, 종료하면 원래대로 돌아갑니다. "
                 + "재부팅해도 남지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
            Button("HID 매핑 강제 해제") { model.forceResetHIDMapping() }
                .font(.caption)
        }
    }

    private var configCard: some View {
        card(title: "설정 파일", tint: model.isConfigReadOnly ? .orange : .secondary) {
            Text(model.configFileURL.path)
                .font(.caption).monospaced()
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
            if model.isConfigReadOnly {
                Text("읽기 전용: 파일 버전이 이 앱보다 높습니다. 저장하지 않습니다.")
                    .font(.caption).bold().foregroundStyle(.orange)
            }
            HStack {
                Button("Finder 에서 보기") { model.revealConfigInFinder() }
                Button("다시 불러오기") { model.reloadConfig() }
                Spacer()
                Text("직접 고치면 자동으로 반영됩니다")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .font(.caption)
            if !model.configWarnings.isEmpty {
                Divider()
                ForEach(Array(model.configWarnings.enumerated()), id: \.offset) { _, warning in
                    Text("• \(warning)").font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private var logCard: some View {
        card(title: "이벤트 로그", tint: .secondary) {
            if model.logEntries.isEmpty {
                Text("아직 기록이 없습니다.").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(model.logEntries) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                        .font(.caption2).monospaced().foregroundStyle(.tertiary)
                                    Text(entry.text).font(.caption).monospaced()
                                }
                                .id(entry.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 200)
                    .onChange(of: model.logEntries.count) {
                        if let last = model.logEntries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                Button("지우기") { model.clearLog() }.font(.caption)
            }
        }
    }

    @ViewBuilder
    private func card<Content: View>(
        title: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(tint == .secondary ? .primary : tint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.2)))
    }
}
