import SwiftUI

/// GitHub 에 쌓인 스냅샷 중 하나를 골라, 항목을 체크해서 가져온다.
///
/// 스냅샷을 고르면 지금 설정과 무엇이 다른지 `ConfigDiffPickerView` 로 보여 준다.
/// 전체를 가져올 수도 있고 몇 개만 골라 가져올 수도 있다.
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
        } else {
            ConfigDiffPickerView(items: items, selectedIDs: $selectedIDs, incomingTitle: "스냅샷")
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
