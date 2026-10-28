import SwiftUI

/// 단축키 에디터. 실제 키보드 배열대로 그린다.
///
/// 레이어가 여럿이면 **같은 뷰**를 공유한다. 레이어를 바꾸면 어떤 `action` 을
/// 키캡에 넘기는지만 달라진다. 지금은 Caps Lock 하나라 레이어 고르는 칸을 숨긴다.
struct KeyboardEditorView: View {

    let model: EngineModel

    @State private var selectedLayer: LayerKey = .capsLock
    @State private var selectedKeyIdentifier: String?
    /// 앱 피커 팝오버가 붙어 있는 키. 어느 키를 고치는 중인지 화살표가 가리킨다.
    @State private var pickerKeyIdentifier: String?
    /// 드래그 중인 키캡이 올라와 있는 키.
    @State private var dropTargetIdentifier: String?
    /// 이미 사용 중인 키에 덮어쓰기 전 확인 대기 중인 (키, 기존, 새 동작).
    @State private var pendingAssignment: PendingAssignment?

    private struct PendingAssignment: Equatable {
        let keyIdentifier: String
        let existing: ShortcutAction
        let replacement: ShortcutAction
    }

    /// 드래그 페이로드 접두사. 레이어 이름까지 넣어서 다른 앱에서 끌어온 텍스트나
    /// 다른 레이어의 키캡이 잘못 떨어지는 것을 막는다.
    private static let dragPrefix = "capslockcontrol.shortcut"

    /// 모디파이어처럼 단축키로 쓸 수 없는 키까지 그릴지.
    /// 두 배치를 눈으로 비교할 수 있게 전환식으로 둔다.
    @AppStorage("editor.showFixedKeys") private var showFixedKeys = true

    private var bindings: [String: ShortcutAction] {
        model.config.layers[selectedLayer.rawValue] ?? [:]
    }

    private var usedCount: Int { bindings.count }
    /// 셀 수 있는 건 실제로 걸 수 있는 키뿐이다. 모디파이어는 애초에 표에 없다.
    private var availableCount: Int { max(0, KeyCodeTable.all.count - usedCount) }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 16) {
                layerPicker
                if model.config.layers.values.allSatisfy(\.isEmpty) { emptyStateHint }
                keyboard
                detailPanel
            }
            .padding(20)
        }
        .onAppear(perform: openPickerIfRequestedByLaunchArgument)
        // 창을 닫아도 Window 씬은 이 뷰를 버리지 않고 숨겨 둔다. 그대로 두면 다시 열었을 때
        // 지난번에 고른 키가 파랗게 남아 있다.
        .onDisappear(perform: clearSelection)
        .sheet(isPresented: Binding(get: { pickerKeyIdentifier != nil },
                                    set: { if !$0 { pickerKeyIdentifier = nil } })) {
            if let identifier = pickerKeyIdentifier {
                ApplicationPickerView(
                    title: "\(selectedLayer.shortName) + \(label(for: identifier))",
                    existingBindings: bindings,
                    mediaTarget: model.config.defaults.mediaTarget,
                    onCancel: { pickerKeyIdentifier = nil },
                    onSelect: { picked in assign(picked, to: identifier) }
                )
            }
        }
        .alert("이미 사용 중인 키입니다",
               isPresented: Binding(get: { pendingAssignment != nil },
                                    set: { if !$0 { pendingAssignment = nil } }),
               presenting: pendingAssignment) { assignment in
            Button("취소", role: .cancel) { pendingAssignment = nil }
            Button("교체") {
                commit(assignment.replacement, to: assignment.keyIdentifier)
                pendingAssignment = nil
            }
        } message: { assignment in
            let label = KeyCodeTable.entry(forIdentifier: assignment.keyIdentifier)?.label
                ?? assignment.keyIdentifier
            Text("\(selectedLayer.shortName) + \(label) 는 현재 "
                 + "\(assignment.existing.displayName) 에 할당되어 있습니다.\n"
                 + "\(assignment.replacement.displayName) 으로 교체할까요?")
        }
    }

    // MARK: - 레이어 선택 + 개수

    private var layerPicker: some View {
        HStack(alignment: .center, spacing: 14) {
            if LayerKey.allCases.count > 1 {
                Picker("", selection: $selectedLayer) {
                    ForEach(LayerKey.allCases, id: \.self) { layer in
                        Text(layer.displayName).tag(layer)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .onChange(of: selectedLayer) {
                    clearSelection()
                }
            }

            Picker("", selection: $showFixedKeys) {
                Text("전체 키보드").tag(true)
                Text("단축키 키만").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("모디파이어처럼 단축키로 쓸 수 없는 키를 그릴지 고릅니다")

            Spacer()

            countBadge(label: "Used", value: usedCount, tint: .accentColor)
            countBadge(label: "Available", value: availableCount, tint: .secondary)
            if missingCountInLayer > 0 {
                countBadge(label: "Missing", value: missingCountInLayer, tint: .red)
            }
        }
    }

    /// 처음 쓰는 사람에게는 빈 키보드만 보인다. 무엇을 하면 되는지 한 줄 알려 준다.
    private var emptyStateHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap").foregroundStyle(.tint)
            Text("아직 단축키가 없습니다. 아래 빈 키를 누르면 실행할 앱을 고를 수 있습니다.")
                .font(.callout)
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.3)))
    }

    private var missingCountInLayer: Int {
        bindings.values.filter { !model.isInstalled($0) }.count
    }

    private func countBadge(label: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text("\(value)").font(.caption).bold().foregroundStyle(tint)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.1)))
    }

    // MARK: - 키보드

    private var keyboard: some View {
        VStack(alignment: .leading, spacing: KeyboardLayout.gap) {
            ForEach(KeyboardLayout.rows) { row in
                let indent = KeyboardLayout.indent(of: row, showingFixedKeys: showFixedKeys)
                HStack(spacing: KeyboardLayout.gap) {
                    if indent > 0 {
                        Color.clear.frame(width: KeyboardLayout.indentWidth(indent), height: 1)
                    }
                    // 한 행에 같은 라벨의 키가 두 번 나온다(command, option, shift).
                    // 라벨로 id 를 만들면 ForEach 가 둘을 같은 것으로 보고 엉뚱한 내용을
                    // 그린다. 배치는 고정이므로 위치를 id 로 쓴다.
                    let elements = KeyboardLayout.elements(of: row, showingFixedKeys: showFixedKeys)
                    ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                        // 모디파이어를 지워도 방향키는 원래 자리(오른쪽 끝)에 있어야 한다.
                        if case .arrows = element { Spacer(minLength: 0) }
                        view(for: element)
                    }
                }
                .frame(width: KeyboardLayout.totalWidth, alignment: .leading)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
    }

    @ViewBuilder
    private func view(for element: KeyboardLayout.Element) -> some View {
        switch element {
        case .key(let identifier, let units):
            if let entry = KeyCodeTable.entry(forIdentifier: identifier) {
                keycap(for: entry, width: KeyboardLayout.width(units))
            }
        case .fixed(let key, let units):
            FixedKeycapView(key: key,
                            width: KeyboardLayout.width(units),
                            height: KeyboardLayout.keyHeight,
                            config: model.config)
        case .arrows:
            arrowCluster
        }
    }

    /// 맥북의 역T자 방향키. **네 개 모두 반 높이**이고 ← ↓ → 가 바닥에 나란히 붙는다.
    /// ↑ 만 ↓ 위에 얹힌다.
    private var arrowCluster: some View {
        let full = KeyboardLayout.keyHeight
        let half = (full - KeyboardLayout.gap) / 2
        return HStack(alignment: .bottom, spacing: KeyboardLayout.gap) {
            arrowKeycap("left", height: half)
            VStack(spacing: KeyboardLayout.gap) {
                arrowKeycap("up", height: half)
                arrowKeycap("down", height: half)
            }
            arrowKeycap("right", height: half)
        }
        .frame(height: full, alignment: .bottom)
    }

    @ViewBuilder
    private func arrowKeycap(_ identifier: String, height: CGFloat) -> some View {
        if let entry = KeyCodeTable.entry(forIdentifier: identifier) {
            keycap(for: entry, width: KeyboardLayout.width(1), height: height)
        }
    }

    private func keycap(
        for entry: KeyCodeTable.Entry,
        width: CGFloat,
        height: CGFloat = KeyboardLayout.keyHeight
    ) -> some View {
        let action = bindings[entry.identifier]
        let cap = KeycapView(
            label: entry.label,
            width: width,
            height: height,
            action: action,
            isInstalled: action.map { model.isInstalled($0) } ?? true,
            isSelected: selectedKeyIdentifier == entry.identifier,
            isDropTarget: dropTargetIdentifier == entry.identifier,
            onTap: { handleTap(on: entry.identifier) }
        )
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items.first, onto: entry.identifier)
        } isTargeted: { isTargeted in
            updateDropTarget(entry.identifier, isTargeted: isTargeted)
        }
        return makeDraggable(cap, identifier: entry.identifier,
                             isEnabled: action != nil && model.isEditable)
    }

    /// 빈 키는 끌 것이 없고, 읽기 전용이면 옮기면 안 된다.
    @ViewBuilder
    private func makeDraggable(_ view: some View, identifier: String, isEnabled: Bool) -> some View {
        if isEnabled {
            view.draggable("\(Self.dragPrefix)/\(selectedLayer.rawValue)/\(identifier)")
        } else {
            view
        }
    }

    // MARK: - 선택 / 할당

    private func label(for identifier: String) -> String {
        KeyCodeTable.entry(forIdentifier: identifier)?.label ?? identifier
    }

    private func handleTap(on identifier: String) {
        // 빈 키를 누르면 바로 추가 UI 를 띄운다.
        guard bindings[identifier] != nil else {
            selectedKeyIdentifier = identifier
            guard model.isEditable else {
                model.note("\(selectedLayer.shortName) + \(label(for: identifier)) — 읽기 전용이라 편집할 수 없습니다")
                return
            }
            model.note("\(selectedLayer.shortName) + \(label(for: identifier)) 에 할당할 항목을 고릅니다")
            pickerKeyIdentifier = identifier
            return
        }
        selectedKeyIdentifier = selectedKeyIdentifier == identifier ? nil : identifier
    }

    private func clearSelection() {
        selectedKeyIdentifier = nil
        pickerKeyIdentifier = nil
        dropTargetIdentifier = nil
    }

    /// 피커에서 고른 결과를 받는다. 이미 뭔가 걸려 있으면 확인을 먼저 받는다.
    private func assign(_ action: ShortcutAction, to identifier: String) {
        pickerKeyIdentifier = nil
        guard let existing = bindings[identifier] else {
            commit(action, to: identifier)
            return
        }
        guard existing != action else { return }
        pendingAssignment = PendingAssignment(
            keyIdentifier: identifier, existing: existing, replacement: action)
    }

    private func commit(_ action: ShortcutAction, to identifier: String) {
        model.note("\(selectedLayer.shortName) + \(label(for: identifier)) ← \(action.displayName)")
        model.setAction(action, layer: selectedLayer, keyIdentifier: identifier)
        selectedKeyIdentifier = identifier
    }

    // MARK: - 드래그로 옮기기

    private func updateDropTarget(_ identifier: String, isTargeted: Bool) {
        if isTargeted {
            dropTargetIdentifier = identifier
        } else if dropTargetIdentifier == identifier {
            dropTargetIdentifier = nil
        }
    }

    /// 키캡을 다른 키에 떨어뜨렸을 때. 양쪽을 맞바꾸므로 아무것도 잃지 않는다.
    /// 빈 키에 떨어뜨리면 그냥 이동이 된다.
    private func handleDrop(_ payload: String?, onto identifier: String) -> Bool {
        dropTargetIdentifier = nil
        guard model.isEditable, let payload else { return false }
        let prefix = "\(Self.dragPrefix)/\(selectedLayer.rawValue)/"
        guard payload.hasPrefix(prefix) else { return false }
        let source = String(payload.dropFirst(prefix.count))
        guard source != identifier,
              KeyCodeTable.entry(forIdentifier: source) != nil,
              bindings[source] != nil else { return false }
        model.swapActions(source, identifier, layer: selectedLayer)
        selectedKeyIdentifier = identifier
        return true
    }

    /// 개발용. `CapsLockControl.app --args -openPicker q` 로 실행하면 Q 키의 앱 피커를
    /// 바로 열어 준다. 클릭 자동화 없이 팝오버 모양을 확인할 때 쓴다.
    private func openPickerIfRequestedByLaunchArgument() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-openPicker"),
              let identifier = arguments[safe: index + 1],
              KeyCodeTable.entry(forIdentifier: identifier) != nil else { return }
        selectedKeyIdentifier = identifier
        // 창이 key window 가 되기 전에 팝오버를 띄우면 AppKit 이 바로 닫아 버린다.
        Task {
            try? await Task.sleep(for: .seconds(1))
            pickerKeyIdentifier = identifier
        }
        #endif
    }

    // MARK: - 선택한 키 정보

    @ViewBuilder
    private var detailPanel: some View {
        if let identifier = selectedKeyIdentifier,
           KeyCodeTable.entry(forIdentifier: identifier) != nil {
            KeyDetailView(
                model: model,
                layer: selectedLayer,
                keyIdentifier: identifier,
                action: bindings[identifier],
                pickerKeyIdentifier: $pickerKeyIdentifier
            )
        } else {
            Text("빈 키를 누르면 앱을 고를 수 있고, 할당된 키를 누르면 상세 정보가 열립니다. "
                 + "키캡을 끌어서 다른 키로 옮길 수도 있습니다(양쪽이 맞바뀝니다).")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }
}

#if DEBUG
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
