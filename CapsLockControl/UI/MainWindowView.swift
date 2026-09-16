import SwiftUI

/// 창 전체. 어느 탭에 있어도 보여야 하는 것(엔진 상태·권한 경고)은 탭 위에 둔다.
struct MainWindowView: View {
    let model: EngineModel

    enum Tab: Hashable {
        case keyLayout
        case status
    }

    @State private var tab: Tab = .keyLayout

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                header
                if !model.isTrusted { permissionBanner }
                if !model.conflictingApps.isEmpty { conflictBanner }
                if let error = model.lastError { errorBanner(error) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            TabView(selection: $tab) {
                KeyboardEditorView(model: model)
                    .tabItem { Label("Key Layout", systemImage: "keyboard") }
                    .tag(Tab.keyLayout)
                StatusView(model: model)
                    .tabItem { Label("Status", systemImage: "info.circle") }
                    .tag(Tab.status)
            }
            .padding(.top, 8)
        }
        .frame(minWidth: 880, minHeight: 700)
    }

    // MARK: - 헤더

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CapsLock Control").font(.title2).bold()
                Text(model.isEngineRunning
                     ? "동작 중 · 단축키 \(model.bindingCount)개"
                     : "정지됨")
                    .font(.caption)
                    .foregroundStyle(model.isEngineRunning ? .green : .secondary)
            }
            Spacer()
            layerIndicator
            Button(model.isEngineRunning ? "정지" : "시작") { model.toggle() }
                .disabled(!model.isTrusted && !model.isEngineRunning)
            // 메뉴바 아이콘이 가려져 보이지 않을 수 있다. 설정으로 가는 길이
            // 메뉴바 하나뿐이면 그때 막힌다.
            Button {
                WindowOpener.shared.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("설정 (Export / Import 포함)")
        }
    }

    /// 레이어 키를 누르고 있는 동안 실시간으로 켜진다. 동작 확인에 제일 유용한 표시다.
    private var layerIndicator: some View {
        HStack(spacing: 6) {
            ForEach(LayerKey.allCases, id: \.self) { layer in
                Text(layer.shortName)
                    .font(.caption).monospaced()
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(model.activeLayer == layer
                                  ? Color.accentColor : Color.secondary.opacity(0.15))
                    )
                    .foregroundStyle(model.activeLayer == layer ? Color.white : Color.secondary)
            }
        }
    }

    // MARK: - 배너

    private var permissionBanner: some View {
        banner(tint: .orange, icon: "exclamationmark.triangle.fill") {
            VStack(alignment: .leading, spacing: 6) {
                Text("손쉬운 사용 권한이 필요합니다").font(.callout).bold()
                Text("시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용 에서 CapsLock Control 을 켜 주세요. "
                     + "허용하면 자동으로 시작합니다.")
                    .font(.caption)
                Button("시스템 설정 열기") { model.requestAccessibilityPermission() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private var conflictBanner: some View {
        banner(tint: .yellow, icon: "bolt.trianglebadge.exclamationmark.fill") {
            VStack(alignment: .leading, spacing: 4) {
                Text("다른 키보드 도구가 실행 중입니다: \(model.conflictingApps.joined(separator: ", "))")
                    .font(.callout).bold()
                Text("같은 키를 두 도구가 가로채면 동작이 겹칩니다. 직접 종료해 주세요. "
                     + "CapsLock Control 은 다른 앱을 종료하지 않습니다.")
                    .font(.caption)
                Button("다시 확인") { model.refreshConflictingApps() }
                    .controlSize(.small)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        banner(tint: .red, icon: "xmark.octagon.fill") {
            Text(message).font(.callout)
        }
    }

    @ViewBuilder
    private func banner<Content: View>(
        tint: Color,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            content()
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.35)))
    }
}
