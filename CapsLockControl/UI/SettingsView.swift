import SwiftUI
import UniformTypeIdentifiers

/// 설정 창. 메뉴바 › Settings... 로 열린다.
struct SettingsView: View {
    let model: EngineModel

    @State private var launchState = LaunchAtLogin.state
    @State private var launchError: String?
    /// 슬라이더를 끄는 동안의 값. 놓을 때 한 번만 저장한다(끄는 동안 파일을 계속 쓰지 않게).
    @State private var tapTimeoutDraft: Double?
    /// 파일로 내보내거나 가져온 결과. 저장 창은 닫히고 나면 아무것도 남기지 않아서 여기서 알려 준다.
    @State private var fileResult: FileResult?

    private struct FileResult {
        var text: String
        var isFailure: Bool
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("일반", systemImage: "gearshape") }
            advancedTab
                .tabItem { Label("고급", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 520, height: 640)
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

    // MARK: - 탭

    /// 처음 쓰는 사람도 손댈 만한 것.
    private var generalTab: some View {
        Form {
            Section("일반") {
                launchAtLoginRow
            }
            .disabled(!model.isEditable)

            // 설정 파일과 상관없으니 파일이 읽기 전용이어도 누를 수 있어야 한다.
            Section("업데이트") {
                updateRow
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
                     + "안에 떼면 원래 Caps Lock 기능이 동작합니다. 시간은 고급 탭에서 바꿉니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!model.isEditable)

            Section("백업") { backupSection }
        }
        .formStyle(.grouped)
    }

    /// 새 버전은 알아서 확인한다. 여기서는 지금 버전을 보여 주고 바로 물어볼 수 있게만 한다.
    private var updateRow: some View {
        let updates = model.updates
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("지금 버전 v\(updates.currentVersion)")
                Spacer()
                if let update = updates.available {
                    Button(updates.isInstalling ? "업데이트 받는 중…" : "v\(update.version) 설치") {
                        updates.install()
                    }
                    .disabled(updates.isInstalling)
                } else {
                    Button(updates.isChecking ? "확인 중…" : "지금 확인") {
                        Task { await updates.check() }
                    }
                    .disabled(updates.isChecking)
                }
            }
            Text(updateStatusText)
                .font(.caption)
                .foregroundStyle(updates.installFailure == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var updateStatusText: String {
        let updates = model.updates
        if let failure = updates.installFailure { return failure }
        switch updates.lastResult {
        case .available:
            return "새 버전이 나왔습니다. 설치하면 앱이 잠깐 꺼졌다가 새 버전으로 다시 켜집니다."
        case .upToDate:
            return "최신 버전입니다. 새 버전은 몇 시간마다 알아서 확인합니다."
        case .failed:
            return "새 버전을 확인하지 못했습니다. 인터넷 연결을 확인해 주세요."
        case nil:
            return "새 버전은 몇 시간마다 알아서 확인합니다."
        }
    }

    /// 처음 쓰는 사람은 몰라도 되는 설정.
    /// 다른 키를 바꾸는 설정은 모르고 켜면 평소 쓰던 키가 사라지므로 전부 꺼진 채로 시작한다.
    private var advancedTab: some View {
        Form {
            // 기본값 "무시하기" 가 안전해서 대부분 바꿀 일이 없다.
            Section("레이어 세부 동작") {
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

                tapTimeoutRow
            }

            Section {
                Toggle("fn 과 왼쪽 Control 맞바꾸기", isOn: Binding(
                    get: { model.config.modifiers.swapFnAndLeftControl },
                    set: { model.setSwapFnAndLeftControl($0) }
                ))
                Text("Apple 키보드(내장·Magic Keyboard)에서만 동작합니다.")
                    .font(.caption).foregroundStyle(.secondary)

                Picker("Right Command", selection: Binding(
                    get: { model.config.rightCommand.action },
                    set: { model.setRightCommandAction($0) }
                )) {
                    ForEach(RightCommandAction.allCases, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                Text("F18 로 바꾸면 시스템 설정 › 키보드 › 키보드 단축키 › 입력 소스 에서 "
                     + "\"이전 입력 소스 선택\" 에 F18 을 지정해야 오른쪽 ⌘ 로 입력 소스가 바뀝니다. "
                     + "지정하지 않으면 오른쪽 ⌘ 가 아무 일도 하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("다른 키 바꾸기")
            } footer: {
                Text("Caps Lock 말고 다른 키의 동작을 바꿉니다. 필요할 때만 켜세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // 기본값 "시스템 전체" 면 하드웨어 미디어 키와 같아서 대부분 바꿀 일이 없다.
            // Spotify·YouTube Music 전용은 자동화 권한이나 Chrome 설정이 따로 필요하다.
            Section("미디어 키") { mediaSection }

            // SSH 키와 git 저장소가 있어야 쓸 수 있다. Mac 이 하나면 필요 없다.
            Section("GitHub 동기화") { syncSection }

            // JSON 을 손으로 고치는 사람만 쓴다.
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
        .disabled(!model.isEditable)
    }

    // MARK: - 백업

    /// GitHub 없이 단축키를 파일 하나로 남긴다. 다른 Mac 으로 옮길 때도 이 파일을 쓴다.
    @ViewBuilder
    private var backupSection: some View {
        HStack {
            Button("파일로 내보내기...") { exportToFile() }
            Spacer()
        }
        if let fileResult {
            Text(fileResult.text)
                .font(.caption)
                .foregroundStyle(fileResult.isFailure ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text("지금 단축키와 설정을 JSON 파일 하나로 저장합니다.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = ConfigFile.suggestedName(for: Date())
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportConfig(to: url)
            fileResult = FileResult(text: "\(url.lastPathComponent) 로 내보냈습니다.", isFailure: false)
        } catch {
            fileResult = FileResult(text: "내보내지 못했습니다: \(error.localizedDescription)",
                                    isFailure: true)
        }
    }

    // MARK: - 탭 판정 시간

    @ViewBuilder
    private var tapTimeoutRow: some View {
        let range = CapsLockControlConfig.Defaults.tapTimeoutRange
        let value = tapTimeoutDraft ?? Double(model.config.defaults.layerTapTimeoutMilliseconds)
        LabeledContent("Caps Lock 단독 탭 판정 시간") {
            HStack(spacing: 8) {
                // step 을 주면 macOS 는 10ms 마다 눈금을 촘촘히 찍는다. 값만 10ms 로 맞춘다.
                Slider(value: Binding(get: { value },
                                      set: { tapTimeoutDraft = ($0 / 10).rounded() * 10 }),
                       in: Double(range.lowerBound)...Double(range.upperBound)) { isEditing in
                    guard !isEditing, let draft = tapTimeoutDraft else { return }
                    model.setLayerTapTimeout(milliseconds: Int(draft))
                    tapTimeoutDraft = nil
                }
                .frame(width: 180)
                Text("\(Int(value))ms")
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
        }
        // 단독 탭을 끈 상태면 이 시간은 아무 데도 쓰이지 않는다.
        .disabled(!model.config.defaults.capsLockTapTogglesCapsLock)
        Text("Caps Lock 을 이 시간 안에 떼야 대문자 고정으로 칩니다. 짧을수록 레이어를 쓰려다 "
             + "그냥 놓았을 때 대문자 고정이 덜 켜지고, 길수록 천천히 눌러도 대문자 고정이 됩니다.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 미디어 키

    /// 재생/다음/이전을 어디로 보낼지.
    ///
    /// 시스템 미디어 키는 "지금 재생 중인 앱" 에게 간다. 브라우저에 유튜브 탭이
    /// 떠 있으면 그쪽이 먼저 받는다. Spotify 만 조종하려면 대상을 바꿔야 한다.
    @ViewBuilder
    private var mediaSection: some View {
        let current = model.config.defaults.mediaTarget
        Picker("새 미디어 단축키를 보낼 곳", selection: Binding(
            get: { current },
            set: { model.setMediaTargetDefault($0) }
        )) {
            ForEach(MediaTarget.allCases, id: \.self) { target in
                Text(target.displayName).tag(target)
            }
        }
        Text(current.detail)
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        // 기본값만 바꾸면 이미 걸어 둔 단축키는 그대로다. 그건 거의 항상 실수다.
        let stragglers = model.mediaShortcutCount(otherThan: current)
        if stragglers > 0 {
            HStack {
                Text("이미 만든 미디어 단축키 \(stragglers)개가 다른 곳을 봅니다.")
                    .font(.caption).foregroundStyle(.orange)
                Spacer()
                Button("전부 \(current.displayName) 으로") {
                    model.moveAllMediaShortcuts(to: current)
                }
                .controlSize(.small)
                .disabled(!model.isEditable)
            }
        }
    }

    // MARK: - 동기화

    @ViewBuilder
    private var syncSection: some View {
        TextField("저장소 주소", text: Binding(
            get: { model.sync.remoteURL },
            set: { model.sync.remoteURL = $0 }
        ), prompt: Text("git@github.com:사용자/capslock-control-config.git"))
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
            Text("이 앱이 응용 프로그램 폴더에 없습니다. 로그인 항목은 앱이 지금 있는 위치를 "
                 + "기억하므로, 나중에 앱을 옮기면 조용히 실행되지 않습니다. "
                 + "응용 프로그램 폴더로 옮긴 뒤 켜 주세요.")
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
