import SwiftUI

/// 선택한 키 하나의 상세 정보와 편집 버튼.
///
/// 할당/교체는 부모(KeyboardEditorView)가 처리한다. 앱 피커 팝오버가 키캡에
/// 붙어 있어서, 어느 키를 고치는 중인지 화살표가 가리켜 주기 때문이다.
struct KeyDetailView: View {

    let model: EngineModel
    let layer: LayerKey
    let keyIdentifier: String
    let action: ShortcutAction?
    /// 이 값을 keyIdentifier 로 바꾸면 키캡에 붙은 피커가 열린다.
    @Binding var pickerKeyIdentifier: String?

    private var keyLabel: String {
        KeyCodeTable.entry(forIdentifier: keyIdentifier)?.label ?? keyIdentifier.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(layer.shortName) + \(keyLabel)")
                .font(.headline).monospaced()

            if let action {
                assigned(action)
            } else {
                Text("비어 있습니다.").font(.callout).foregroundStyle(.secondary)
            }

            Divider()
            buttons
            if !model.isEditable {
                Text("설정 파일이 읽기 전용이라 편집할 수 없습니다.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.2)))
    }

    // MARK: - 버튼

    private var buttons: some View {
        HStack(spacing: 8) {
            if action == nil {
                Button("앱 할당...") { pickerKeyIdentifier = keyIdentifier }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.isEditable)
            } else {
                Button("변경...") { pickerKeyIdentifier = keyIdentifier }
                    .disabled(!model.isEditable)
                Button("단축키 삭제", role: .destructive) {
                    model.setAction(nil, layer: layer, keyIdentifier: keyIdentifier)
                }
                .disabled(!model.isEditable)
            }
            Spacer()
            Button("설정 파일 열기") { model.revealConfigInFinder() }
                .font(.caption)
        }
    }

    // MARK: - 할당된 내용

    @ViewBuilder
    private func assigned(_ action: ShortcutAction) -> some View {
        switch action {
        case .application(let target):
            HStack(spacing: 10) {
                if let icon = AppIconProvider.shared.icon(forBundleIdentifier: target.bundleIdentifier) {
                    Image(nsImage: icon).resizable().frame(width: 32, height: 32)
                        .missingAppStyle(!model.isInstalled(action), badgeSize: 13)
                } else {
                    Image(systemName: "questionmark.app.dashed")
                        .font(.system(size: 26)).foregroundStyle(.red)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(target.displayName.isEmpty ? target.bundleIdentifier : target.displayName)
                            .font(.callout).bold()
                        if !model.isInstalled(action) {
                            Text("Missing")
                                .font(.caption2).bold()
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Color.red.opacity(0.15)))
                                .foregroundStyle(.red)
                        }
                    }
                    Text(target.bundleIdentifier)
                        .font(.caption).monospaced().foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
            }
            behaviorPicker(for: target)

        case .media(let command, let target):
            HStack(spacing: 10) {
                Image(systemName: command == .playPause ? "playpause.fill"
                                 : command == .next ? "forward.fill" : "backward.fill")
                    .font(.system(size: 24)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.displayName).font(.callout).bold()
                    Text(target.displayName)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            mediaTargetPicker(current: target)

        case .keyStroke(let stroke):
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.system(size: 22)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stroke.comboString).font(.title3).monospaced().bold()
                    Text(stroke.label.flatMap { $0.isEmpty ? nil : $0 }
                         ?? "이 조합을 등록해 둔 앱이 반응합니다")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text("CapsLock Control 이 이 조합을 대신 눌러 줍니다. 받을 앱에서 같은 조합을 "
                 + "전역 단축키로 등록해 두어야 합니다.")
                .font(.caption).foregroundStyle(.secondary)
            KeyStrokeEditor(model: model, layer: layer, keyIdentifier: keyIdentifier, stroke: stroke)

        case .unsupported(let rawType):
            Text("이 버전이 모르는 동작 타입입니다: \(rawType)")
                .font(.callout).foregroundStyle(.orange)
        }
    }

    /// 미디어 명령을 어디로 보낼지.
    ///
    /// 기본값인 시스템 미디어 키는 "지금 재생 중인 앱" 에게 간다. 브라우저에 유튜브
    /// 탭이 떠 있으면 그쪽이 받아 가서, Spotify 만 조종하려던 의도가 깨진다.
    private func mediaTargetPicker(current: MediaTarget) -> some View {
        let selection = Binding<MediaTarget>(
            get: { current },
            set: { model.setMediaTarget($0, layer: layer, keyIdentifier: keyIdentifier) }
        )
        return VStack(alignment: .leading, spacing: 4) {
            Picker("보낼 곳", selection: selection) {
                ForEach(MediaTarget.allCases, id: \.self) { target in
                    Text(target.displayName).tag(target)
                }
            }
            .pickerStyle(.menu)
            .font(.caption)
            .disabled(!model.isEditable)

            Text(current.detail)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.mediaShortcutCount(otherThan: current) > 0 {
                Button("나머지 미디어 단축키도 \(current.displayName) 으로") {
                    model.moveAllMediaShortcuts(to: current)
                }
                .controlSize(.small)
                .disabled(!model.isEditable)
            }
        }
    }

    /// 이 앱이 이미 맨 앞일 때 같은 키를 다시 눌렀을 때의 동작.
    private func behaviorPicker(for target: ApplicationTarget) -> some View {
        let selection = Binding<AlreadyActiveBehavior?>(
            get: { target.whenAlreadyActive },
            set: { model.setWhenAlreadyActive($0, layer: layer, keyIdentifier: keyIdentifier) }
        )
        return Picker("이미 맨 앞일 때", selection: selection) {
            Text("전역 기본값 · \(model.config.defaults.whenAlreadyActive.displayName)")
                .tag(AlreadyActiveBehavior?.none)
            ForEach(AlreadyActiveBehavior.allCases, id: \.self) { behavior in
                Text(behavior.displayName).tag(AlreadyActiveBehavior?.some(behavior))
            }
        }
        .pickerStyle(.menu)
        .font(.caption)
        .disabled(!model.isEditable)
    }
}


/// keyStroke 동작의 조합과 이름을 고치는 줄.
private struct KeyStrokeEditor: View {
    let model: EngineModel
    let layer: LayerKey
    let keyIdentifier: String
    let stroke: KeyStroke

    @State private var label: String = ""
    @FocusState private var isLabelFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            KeyStrokeRecorder(stroke: stroke) { recorded in
                guard let recorded else {
                    model.setAction(nil, layer: layer, keyIdentifier: keyIdentifier)
                    return
                }
                var updated = recorded
                updated.label = stroke.label
                model.setAction(.keyStroke(updated), layer: layer, keyIdentifier: keyIdentifier)
            }
            .frame(width: 150, height: 26)

            TextField("이름 (선택)", text: $label)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
                .focused($isLabelFocused)
                .onSubmit(commitLabel)
                .onChange(of: isLabelFocused) { _, focused in
                    if !focused { commitLabel() }
                }
            Spacer()
        }
        .disabled(!model.isEditable)
        .onAppear { label = stroke.label ?? "" }
        // 다른 키를 고르거나 창을 닫으면 Enter 없이도 이 줄이 사라진다. 치던 이름을 버리지 않는다.
        .onDisappear(perform: commitLabel)
        .onChange(of: stroke) { _, new in
            if !isLabelFocused { label = new.label ?? "" }
        }
    }

    private func commitLabel() {
        guard label != (stroke.label ?? "") else { return }
        model.setKeyStrokeLabel(label, layer: layer, keyIdentifier: keyIdentifier)
    }
}
