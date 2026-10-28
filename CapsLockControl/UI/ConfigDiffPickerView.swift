import SwiftUI

/// 지금 설정과 가져올 설정의 차이를 좌우로 놓고, 가져올 항목을 체크하게 한다.
///
/// 차이는 **새로 생김 / 바뀜 / 사라짐** 으로 나눠 보여 준다.
/// 어디서 가져오는지(GitHub 스냅샷, 파일)는 이 화면이 모른다. 감싸는 화면이 정한다.
struct ConfigDiffPickerView: View {
    let items: [ConfigDiff.Item]
    @Binding var selectedIDs: Set<String>
    /// 오른쪽 칸 제목. 가져오는 쪽 이름이다.
    let incomingTitle: String

    private var additions: [ConfigDiff.Item] { items.filter(\.isAddition) }
    private var removals: [ConfigDiff.Item] { items.filter(\.isRemoval) }
    private var changes: [ConfigDiff.Item] {
        items.filter { !$0.isAddition && !$0.isRemoval }
    }

    var body: some View {
        if items.isEmpty {
            VStack(spacing: 4) {
                Spacer()
                Image(systemName: "checkmark.circle").font(.title2).foregroundStyle(.green)
                Text("지금 설정과 같습니다. 가져올 것이 없습니다.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            columnHeader(incomingTitle, tint: .green)
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
}
