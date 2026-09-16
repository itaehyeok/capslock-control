import SwiftUI

/// 단축키에 걸 동작을 고르는 팝오버.
///
/// 경로나 bundle ID 를 직접 입력하게 하지 않는다. 목록에서 고르기만 하면 된다.
/// 검색은 Enter 를 누를 필요 없이 **한 글자 칠 때마다** 즉시 걸러진다.
struct ApplicationPickerView: View {

    /// "Caps + [" 처럼 어느 키를 고치는 중인지.
    let title: String
    /// 같은 레이어에 이미 걸린 것들. "이미 Caps+C" 힌트를 띄우는 데 쓴다.
    let existingBindings: [String: ShortcutAction]
    let onCancel: () -> Void
    let onSelect: (ShortcutAction) -> Void

    @State private var query = ""
    @FocusState private var isSearchFocused: Bool
    /// 이미 이 레이어에 걸린 앱을 목록에서 뺀다. 기본으로 켜 둔다 —
    /// 대부분은 새 앱을 찾으러 오지, 이미 건 앱을 다시 찾으러 오지 않는다.
    @AppStorage("picker.hideAssignedApps") private var hideAssignedApps = true

    private var catalog: ApplicationCatalog { .shared }

    private var results: (running: [ApplicationCatalog.Entry],
                          installed: [ApplicationCatalog.Entry]) {
        let found = catalog.search(query)
        guard hideAssignedApps else { return found }
        let assigned = assignedKeyLabels
        return (found.running.filter { assigned[$0.bundleIdentifier] == nil },
                found.installed.filter { assigned[$0.bundleIdentifier] == nil })
    }

    private var hiddenCount: Int {
        guard hideAssignedApps else { return 0 }
        let all = catalog.search(query)
        let assigned = assignedKeyLabels
        return (all.running + all.installed)
            .filter { assigned[$0.bundleIdentifier] != nil }.count
    }

    private var mediaMatches: [(command: MediaCommand, label: String)] {
        let all: [(MediaCommand, String)] = [
            (.playPause, "Play/Pause"), (.next, "Next track"), (.previous, "Previous track"),
        ]
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all.map { (command: $0.0, label: $0.1) } }
        return all
            .filter { $0.1.localizedCaseInsensitiveContains(trimmed) || "media".localizedCaseInsensitiveContains(trimmed) }
            .map { (command: $0.0, label: $0.1) }
    }

    /// bundle identifier → 이미 걸려 있는 키 라벨
    private var assignedKeyLabels: [String: String] {
        var result: [String: String] = [:]
        for (identifier, action) in existingBindings {
            guard let target = action.applicationTarget else { continue }
            let label = KeyCodeTable.entry(forIdentifier: identifier)?.label ?? identifier.uppercased()
            result[target.bundleIdentifier] = label
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchField
            filterBar
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    section("실행 중", entries: results.running)
                    section("설치됨", entries: results.installed,
                            isLoading: catalog.isLoadingInstalled)
                    mediaSection
                    if results.running.isEmpty, results.installed.isEmpty, mediaMatches.isEmpty {
                        Text("일치하는 항목이 없습니다.")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(12)
                    }
                }
            }
            Divider()
            keyStrokeSection
        }
        .frame(width: 380, height: 520)
        .onAppear {
            catalog.refreshRunning()
            catalog.loadInstalledIfNeeded()
            isSearchFocused = true
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline).monospaced()
                Text("여기에 할당할 항목을 고르세요").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("취소", action: onCancel)
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    // MARK: - 검색창

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary).font(.caption)
            TextField("앱 검색...", text: $query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit(selectFirstResult)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            Toggle("이미 할당된 앱 숨기기", isOn: $hideAssignedApps)
                .toggleStyle(.checkbox)
                .font(.caption)
            if hiddenCount > 0 {
                Text("\(hiddenCount)개 숨김")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    /// Enter 를 누르면 첫 결과를 고른다.
    private func selectFirstResult() {
        if let first = results.running.first ?? results.installed.first {
            onSelect(action(for: first))
        } else if let media = mediaMatches.first {
            onSelect(.media(command: media.command, target: .system))
        }
    }

    private func action(for entry: ApplicationCatalog.Entry) -> ShortcutAction {
        .application(ApplicationTarget(
            bundleIdentifier: entry.bundleIdentifier,
            displayName: entry.name,
            bundleURLPath: entry.bundleURLPath
        ))
    }

    // MARK: - 목록

    @ViewBuilder
    private func section(
        _ title: String,
        entries: [ApplicationCatalog.Entry],
        isLoading: Bool = false
    ) -> some View {
        if !entries.isEmpty || isLoading {
            sectionHeader(title, count: entries.count, isLoading: isLoading)
            ForEach(entries) { entry in
                Button {
                    onSelect(action(for: entry))
                } label: {
                    HStack(spacing: 8) {
                        if let icon = AppIconProvider.shared.icon(forBundleIdentifier: entry.bundleIdentifier) {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "app.dashed").frame(width: 18, height: 18)
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.name).font(.callout).lineLimit(1)
                            Text(entry.bundleIdentifier)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if let keyLabel = assignedKeyLabels[entry.bundleIdentifier] {
                            Text("이미 \(keyLabel)")
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.15)))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var mediaSection: some View {
        if !mediaMatches.isEmpty {
            sectionHeader("미디어", count: mediaMatches.count, isLoading: false)
            ForEach(mediaMatches, id: \.command) { media in
                Button {
                    onSelect(.media(command: media.command, target: .system))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: media.command == .playPause ? "playpause.fill"
                                         : media.command == .next ? "forward.fill" : "backward.fill")
                            .frame(width: 18).foregroundStyle(.secondary)
                        Text(media.label).font(.callout)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 다른 앱의 전역 단축키를 부르는 조합. 앱 목록과 성격이 달라서 아래에 따로 둔다.
    private var keyStrokeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("키 조합 보내기").font(.caption).bold().foregroundStyle(.secondary)
            KeyStrokeRecorder(stroke: nil) { recorded in
                guard let recorded else { return }
                onSelect(.keyStroke(recorded))
            }
            .frame(height: 26)
            // 문자열을 + 로 이으면 마크다운이 아니라 그냥 글자가 된다.
            // 강조가 필요하면 하나의 리터럴로 써야 한다.
            Text("칸을 클릭한 뒤 원하는 조합을 누르세요. 그 조합을 전역 단축키로 등록해 둔 앱이 반응합니다. Right Option 은 이 앱이 가져갔으므로 **왼쪽** 수정자를 쓰세요.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
    }

    private func sectionHeader(_ title: String, count: Int, isLoading: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption).bold().foregroundStyle(.secondary)
            if isLoading {
                ProgressView().controlSize(.small).scaleEffect(0.6)
            } else {
                Text("\(count)").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
    }
}
