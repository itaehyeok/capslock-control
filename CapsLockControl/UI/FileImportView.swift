import SwiftUI

/// 열어 둔 설정 파일. 고른 시점의 지금 설정과 비교해 둔 차이를 함께 들고 있다.
struct ImportedConfigFile: Identifiable {
    let id = UUID()
    let url: URL
    let items: [ConfigDiff.Item]
}

/// 내보낸 파일 하나를 열어, 항목을 체크해서 가져온다.
///
/// GitHub Import 와 같은 차이 화면을 쓴다. 스냅샷 목록 대신 파일 하나가 있을 뿐이다.
struct FileImportView: View {
    let model: EngineModel
    let file: ImportedConfigFile
    /// 가져온 항목 수를 넘긴다. 그냥 닫으면 nil.
    let onClose: (_ importedCount: Int?) -> Void

    @State private var selectedIDs: Set<String>

    init(model: EngineModel, file: ImportedConfigFile, onClose: @escaping (_ importedCount: Int?) -> Void) {
        self.model = model
        self.file = file
        self.onClose = onClose
        // 처음엔 전부 체크해 둔다. "전체 가져오기" 가 기본 동작이 되는 게 자연스럽다.
        _selectedIDs = State(initialValue: Set(file.items.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ConfigDiffPickerView(items: file.items, selectedIDs: $selectedIDs, incomingTitle: "파일")
            Divider()
            footer
        }
        .frame(width: 600, height: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("파일에서 가져오기").font(.headline)
            Text(file.url.lastPathComponent)
                .font(.caption).monospaced()
                .lineLimit(1).truncationMode(.middle)
            Text("체크한 항목만 가져옵니다. 가져오기 전에 지금 설정은 백업 폴더에 자동으로 남습니다.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
    }

    private var footer: some View {
        HStack {
            Button("닫기") { onClose(nil) }
                .keyboardShortcut(.cancelAction)
            Button("백업 폴더 열기") { NSWorkspace.shared.open(model.backupDirectoryURL) }
                .controlSize(.small)
            Spacer()
            Button("선택한 \(selectedIDs.count)개 가져오기") {
                model.importItems(file.items, selecting: selectedIDs, logPrefix: "파일에서 가져오기 완료")
                onClose(selectedIDs.count)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedIDs.isEmpty)
        }
        .padding(12)
    }
}
