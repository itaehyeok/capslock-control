import SwiftUI

/// GitHub 에 쌓인 스냅샷 중 하나를 골라, 항목을 체크해서 가져온다.
///
/// 스냅샷을 고르면 지금 설정과 무엇이 다른지 **새로 생김 / 바뀜 / 사라짐** 으로
/// 나눠 보여 준다. 전체를 가져올 수도 있고 몇 개만 골라 가져올 수도 있다.
struct SnapshotImportView: View {
    let model: EngineModel
    let onClose: () -> Void

    @State private var selectedSnapshot: GitSync.SnapshotRef?
    @State private var items: [ConfigDiff.Item] = []
    @State private var selectedIDs: Set<String> = []
    @State private var isLoadingDiff = false
    @State private var hasLoadedList = false
    @State private var isConfirmingImport = false
    @State private var isApplying = false

    private var sync: SyncController { model.sync }

    private var additions: [ConfigDiff.Item] { items.filter(\.isAddition) }
    private var removals: [ConfigDiff.Item] { items.filter(\.isRemoval) }
    private var changes: [ConfigDiff.Item] {
        items.filter { !$0.isAddition && !$0.isRemoval }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            snapshotPicker
            Divider()
            diffList
            Divider()
            footer
        }
        .frame(width: 600, height: 560)
        .task {
            guard !hasLoadedList else { return }
            hasLoadedList = true
            await sync.refreshSnapshots()
            if let first = sync.snapshots.first { await select(first) }
        }
        .alert("가져오기 전에 지금 설정을 백업할까요?", isPresented: $isConfirmingImport) {
            Button("Export 하고 가져오기") {
                isApplying = true
                Task {
                    let didImport = await sync.exportThenImport(items, selecting: selectedIDs)
                    isApplying = false
                    if didImport { onClose() }
                }
            }
            Button("그냥 가져오기") {
                sync.importItems(items, selecting: selectedIDs)
                onClose()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("가져오면 지금 설정의 해당 항목은 덮어써집니다.\n\n"
                 + "\"Export 하고 가져오기\" 는 지금 설정을 GitHub 에 새 스냅샷으로 먼저 올립니다. "
                 + "나중에 Import 로 그대로 되돌릴 수 있습니다.\n\n"
                 + "어느 쪽을 고르든 이 Mac 에 로컬 백업 파일이 항상 남습니다.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("GitHub 에서 가져오기").font(.headline)
            Text("스냅샷을 고르면 지금 설정과 무엇이 다른지 보여 줍니다. "
                 + "체크한 항목만 가져옵니다. GitHub 에는 아무것도 올리지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
    }

    // MARK: - 스냅샷 목록

    private var snapshotPicker: some View {
        HStack(spacing: 8) {
            if sync.snapshots.isEmpty {
                // 실패했는데 "스냅샷 없음" 으로 보이면 원인을 영영 못 찾는다.
                // 진짜 오류는 설정 창에만 있었고 그 창은 이 시트에 가려진다.
                Text(snapshotListStatus)
                    .font(.callout)
                    .foregroundStyle(hasListFailure ? Color.red : Color.secondary)
            } else {
                Picker("스냅샷", selection: Binding(
                    get: { selectedSnapshot },
                    set: { reference in
                        guard let reference else { return }
                        Task { await select(reference) }
                    }
                )) {
                    ForEach(sync.snapshots) { reference in
                        Text(reference.displayName).tag(GitSync.SnapshotRef?.some(reference))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320)
                Text("\(sync.snapshots.count)개").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("목록 새로 고침") {
                Task {
                    await sync.refreshSnapshots()
                    if let first = sync.snapshots.first { await select(first) }
                }
            }
            .controlSize(.small)
            .disabled(sync.isWorking)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func select(_ reference: GitSync.SnapshotRef) async {
        selectedSnapshot = reference
        isLoadingDiff = true
        items = await sync.diff(for: reference) ?? []
        // 처음엔 전부 체크해 둔다. "전체 가져오기" 가 기본 동작이 되는 게 자연스럽다.
        selectedIDs = Set(items.map(\.id))
        isLoadingDiff = false
    }

    // MARK: - 차이 목록 (좌우 비교)

    private var hasListFailure: Bool {
        if case .failed = sync.state { return true }
        return false
    }

    private var listFailureMessage: String? {
        if case .failed(let message) = sync.state { return message }
        return nil
    }

    private var snapshotListStatus: String {
        if sync.isWorking { return "목록을 가져오는 중..." }
        if hasListFailure { return "목록을 가져오지 못했습니다" }
        return "올라간 스냅샷이 없습니다. 먼저 Export 해 주세요."
    }

    @ViewBuilder
    private var diffList: some View {
        if let message = listFailureMessage, sync.snapshots.isEmpty {
            failureDetail(message)
        } else if isLoadingDiff {
            centered { ProgressView() }
        } else if selectedSnapshot == nil {
            centered { Text("스냅샷을 고르세요").font(.callout).foregroundStyle(.secondary) }
        } else if items.isEmpty {
            centered {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle").font(.title2).foregroundStyle(.green)
                    Text("지금 설정과 같습니다. 가져올 것이 없습니다.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                summaryBar
                ScrollView {
                    // git diff 처럼 좌우로 놓는다. 같은 키는 한 줄에, 한쪽에만 있는 것은
                    // 그쪽 칸에만 그린다. 빈 칸이 곧 "여기엔 없다" 는 뜻이다.
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                        GridRow {
                            Text("").gridCellUnsizedAxes(.horizontal)
                            columnHeader("지금 설정", tint: .red)
                            columnHeader("스냅샷", tint: .green)
                        }
                        section("새로 생기는 항목", items: additions, icon: "plus.circle.fill", tint: .green)
                        section("바뀌는 항목", items: changes, icon: "arrow.triangle.2.circlepath", tint: .orange)
                        section("사라지는 항목", items: removals, icon: "minus.circle.fill", tint: .red)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private func columnHeader(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption).bold().foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private func section(
        _ title: String,
        items sectionItems: [ConfigDiff.Item],
        icon: String,
        tint: Color
    ) -> some View {
        if !sectionItems.isEmpty {
            GridRow {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(tint).font(.caption2)
                    Text("\(title) \(sectionItems.count)")
                        .font(.caption).bold().foregroundStyle(tint)
                    Spacer()
                    Button(isGroupFullySelected(sectionItems) ? "해제" : "선택") {
                        toggleGroup(sectionItems)
                    }
                    .controlSize(.mini)
                }
                .gridCellColumns(3)
                .padding(.top, 10)
            }
            ForEach(sectionItems) { item in
                GridRow {
                    keyCell(item)
                    valueCell(item.currentDescription, isPresent: !item.isAddition,
                              tint: .red, isSelected: selectedIDs.contains(item.id), item: item)
                    valueCell(item.incomingDescription, isPresent: !item.isRemoval,
                              tint: .green, isSelected: selectedIDs.contains(item.id), item: item)
                }
            }
        }
    }

    private func keyCell(_ item: ConfigDiff.Item) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        return Button {
            toggle(item)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(item.label)
                    .font(.caption).bold().monospaced()
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(width: 150, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 한쪽에만 있는 항목은 없는 쪽을 비워 둔다.
    @ViewBuilder
    private func valueCell(
        _ text: String,
        isPresent: Bool,
        tint: Color,
        isSelected: Bool,
        item: ConfigDiff.Item
    ) -> some View {
        if isPresent {
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(tint.opacity(isSelected ? 0.12 : 0.05)))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(tint.opacity(isSelected ? 0.35 : 0.15)))
                .contentShape(Rectangle())
                .onTapGesture { toggle(item) }
        } else {
            Color.clear
                .frame(height: 24)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { toggle(item) }
        }
    }

    private func toggle(_ item: ConfigDiff.Item) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 8) {
            countBadge("추가", additions.count, .green)
            countBadge("변경", changes.count, .orange)
            countBadge("삭제", removals.count, .red)
            Spacer()
            Button("전체 선택") { selectedIDs = Set(items.map(\.id)) }
            Button("전체 해제") { selectedIDs = [] }
            Text("선택 \(selectedIDs.count)").font(.caption).foregroundStyle(.secondary)
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func countBadge(_ label: String, _ count: Int, _ tint: Color) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.caption)
            Text("\(count)").font(.caption).bold()
        }
        .foregroundStyle(count == 0 ? Color.secondary : tint)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5)
            .fill((count == 0 ? Color.secondary : tint).opacity(0.12)))
    }

    private func isGroupFullySelected(_ groupItems: [ConfigDiff.Item]) -> Bool {
        !groupItems.isEmpty && groupItems.allSatisfy { selectedIDs.contains($0.id) }
    }

    private func toggleGroup(_ groupItems: [ConfigDiff.Item]) {
        if isGroupFullySelected(groupItems) {
            for item in groupItems { selectedIDs.remove(item.id) }
        } else {
            for item in groupItems { selectedIDs.insert(item.id) }
        }
    }

    /// 무엇이 잘못됐는지 이 화면에서 바로 보여 준다.
    private func failureDetail(_ message: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text("GitHub 에서 목록을 가져오지 못했습니다")
                        .font(.callout).bold()
                }
                Text(message)
                    .font(.caption).monospaced()
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
                Divider()
                Text("저장소 주소는 설정 › 동기화에서 고칩니다. 이 Mac 에 GitHub SSH 키가 "
                     + "없다면 공개 저장소에 한해 https 주소로도 가져올 수 있습니다 "
                     + "(내보내기는 인증이 필요합니다).")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("다시 시도") {
                    Task { await sync.refreshSnapshots() }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private func centered<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack { Spacer(); content(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Button("닫기", action: onClose)
                .keyboardShortcut(.cancelAction)
            if let url = sync.backupDirectoryURL {
                Button("백업 폴더 열기") { NSWorkspace.shared.open(url) }
                    .controlSize(.small)
            }
            Spacer()
            if isApplying { ProgressView().controlSize(.small) }
            Button("선택한 \(selectedIDs.count)개 가져오기") {
                isConfirmingImport = true
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedIDs.isEmpty || isLoadingDiff || isApplying)
        }
        .padding(12)
    }
}
