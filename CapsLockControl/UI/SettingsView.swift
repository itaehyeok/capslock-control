import SwiftUI

/// 설정 창. 메뉴바 › Settings... 로 열린다.
struct SettingsView: View {
    let model: EngineModel

    @State private var launchState = LaunchAtLogin.state
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("일반") {
                launchAtLoginRow
            }

            Section("키보드") {
                Toggle("fn 과 왼쪽 Control 맞바꾸기", isOn: Binding(
                    get: { model.config.modifiers.swapFnAndLeftControl },
                    set: { model.setSwapFnAndLeftControl($0) }
                ))
                Text("Karabiner 에서 쓰던 fn ↔ 왼쪽 Control 스왑입니다. "
                     + "Apple 키보드(내장·Magic Keyboard)에서만 동작합니다.")
                    .font(.caption).foregroundStyle(.secondary)

                Picker("Right Command", selection: Binding(
                    get: { model.config.rightCommand.action },
                    set: { model.setRightCommandAction($0) }
                )) {
                    ForEach(RightCommandAction.allCases, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }
            }

            Section("레이어 동작") {
                Picker("앱이 이미 맨 앞일 때", selection: Binding(
                    get: { model.config.defaults.whenAlreadyActive },
                    set: { model.setWhenAlreadyActiveDefault($0) }
                )) {
                    ForEach(AlreadyActiveBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }
                Text("키마다 따로 지정하면 그 키는 이 값을 따르지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Caps Lock 을 짧게 혼자 누르면 대문자 고정", isOn: Binding(
                    get: { model.config.defaults.capsLockTapTogglesCapsLock },
                    set: { model.setCapsLockTapEnabled($0) }
                ))
                Text("다른 키와 조합하지 않고 \(model.config.defaults.layerTapTimeoutMilliseconds)ms "
                     + "안에 떼면 원래 Caps Lock 기능이 동작합니다. "
                     + "시간은 설정 파일의 layerTapTimeoutMilliseconds 로 조절합니다.")
                    .font(.caption).foregroundStyle(.secondary)

                Picker("등록되지 않은 키", selection: Binding(
                    get: { model.config.defaults.unmappedKeyPolicy },
                    set: { model.setUnmappedKeyPolicy($0) }
                )) {
                    ForEach(UnmappedKeyPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                Text(model.config.defaults.unmappedKeyPolicy.explanation)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("동기화") { syncSection }

            Section("설정 파일") {
                Text(model.configFileURL.path)
                    .font(.caption).monospaced().textSelection(.enabled)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Finder 에서 보기") { model.revealConfigInFinder() }
                    Button("다시 불러오기") { model.reloadConfig() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
        .disabled(!model.isEditable)
        .onAppear { launchState = LaunchAtLogin.state }
        .task {
            #if DEBUG
            // 개발용. `--args -openSettings -openImport` 로 Import 화면을 바로 연다.
            if ProcessInfo.processInfo.arguments.contains("-openImport") {
                model.sync.isImportSheetPresented = true
            }
            #endif
        }
        .sheet(isPresented: Binding(
            get: { model.sync.isImportSheetPresented },
            set: { model.sync.isImportSheetPresented = $0 }
        )) {
            SnapshotImportView(model: model) { model.sync.isImportSheetPresented = false }
        }
    }

    // MARK: - 동기화

    @ViewBuilder
    private var syncSection: some View {
        TextField("저장소 주소", text: Binding(
            get: { model.sync.remoteURL },
            set: { model.sync.remoteURL = $0 }
        ), prompt: Text("git@github.com:사용자/keylayer-config.git"))
            .textFieldStyle(.roundedBorder)

        HStack {
            Text(model.sync.statusLine(for: model.config))
                .font(.callout)
                .foregroundStyle(syncTint)
            Spacer()
            Button("Export") {
                Task { await model.sync.export() }
            }
            .disabled(!model.sync.isConfigured || model.sync.isWorking)
            Button("Import...") { model.sync.isImportSheetPresented = true }
                .disabled(!model.sync.isConfigured || model.sync.isWorking)
        }

        if let lastExportedAt = model.sync.lastExportedAt {
            Text("마지막 Export \(lastExportedAt.formatted(date: .abbreviated, time: .shortened))"
                 + (model.sync.lastSummary.map { " · \($0)" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
        }
        if case .failed(let message) = model.sync.state {
            Text(message).font(.caption).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text("Export 는 시각과 Mac 이름이 붙은 새 스냅샷을 올립니다. 기존 것은 지우지 않으므로 "
             + "언제든 되돌릴 수 있습니다. Import 는 그중 하나를 골라 항목별로 가져옵니다. "
             + "토큰이나 키는 저장하지 않고 이 Mac 에 이미 설정된 SSH 인증을 씁니다.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var syncTint: Color {
        switch model.sync.state {
        case .failed: .red
        case .working: .secondary
        case .notConfigured: .secondary
        case .idle: model.sync.hasUnexportedChanges(model.config) ? .orange : .green
        }
    }

    // MARK: - 로그인 시 실행

    @ViewBuilder
    private var launchAtLoginRow: some View {
        Toggle("로그인할 때 자동으로 실행", isOn: Binding(
            get: { launchState.isOn },
            set: { setLaunchAtLogin($0) }
        ))

        if !LaunchAtLogin.isInstalledInApplications {
            // 문자열을 + 로 이으면 마크다운이 아니라 글자가 된다. 백틱을 쓰지 않는다.
            Text("이 앱이 /Applications 에 없습니다. 등록은 앱의 현재 위치를 기억하므로, "
                 + "개발 빌드 경로에서 켜면 앱을 옮기는 순간 조용히 실패합니다. "
                 + "make install 로 설치한 뒤 켜 주세요.")
                .font(.caption).foregroundStyle(.orange)
        }
        if launchState == .requiresApproval {
            VStack(alignment: .leading, spacing: 4) {
                Text("시스템 설정에서 승인이 필요합니다.")
                    .font(.caption).foregroundStyle(.orange)
                Button("로그인 항목 설정 열기") { LaunchAtLogin.openLoginItemsSettings() }
                    .controlSize(.small)
            }
        }
        if let launchError {
            Text(launchError).font(.caption).foregroundStyle(.red)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchError = nil
        } catch {
            launchError = "로그인 항목을 바꾸지 못했습니다: \(error.localizedDescription)"
        }
        launchState = LaunchAtLogin.state
    }
}
