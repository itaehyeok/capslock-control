import SwiftUI

/// 단축키를 걸 수 있는 키 한 칸.
///
/// 두 레이어가 같은 컴포넌트를 공유한다. 레이어마다 다른 건 넘겨받는 `action` 뿐이다.
struct KeycapView: View {

    let label: String
    let width: CGFloat
    let height: CGFloat
    let action: ShortcutAction?
    let isInstalled: Bool
    let isSelected: Bool
    /// 드래그 중인 키캡이 이 위에 올라와 있는지.
    let isDropTarget: Bool
    let onTap: () -> Void

    private var isEmpty: Bool { action == nil }
    /// ↑ ↓ 처럼 반 높이인 키. 라벨·아이콘·이름 세 줄이 들어갈 자리가 없다.
    private var isShort: Bool { height < KeyboardLayout.keyHeight * 0.75 }

    private var borderColor: Color {
        if isDropTarget || isSelected { return .accentColor }
        if isEmpty { return .secondary.opacity(0.25) }
        if !isInstalled { return .red.opacity(0.55) }
        return .secondary.opacity(0.45)
    }

    private var fillColor: Color {
        if isDropTarget { return .accentColor.opacity(0.3) }
        if isSelected { return .accentColor.opacity(0.16) }
        if isEmpty { return .clear }
        return Color(nsColor: .controlBackgroundColor)
    }

    var body: some View {
        Button(action: onTap) {
            content
                .padding(3)
                .frame(width: width, height: height)
                // 반 높이 키에서 내용이 테두리 밖으로 새지 않게 한다.
                .clipped()
            .background(RoundedRectangle(cornerRadius: 7).fill(fillColor))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(borderColor,
                                  style: StrokeStyle(lineWidth: (isSelected || isDropTarget) ? 2 : 1,
                                                     dash: (isEmpty && !isDropTarget) ? [3, 3] : []))
            )
            // 빈 키는 바탕이 투명이라, 이게 없으면 + 글자와 점선 위만 눌린다.
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    @ViewBuilder
    private var content: some View {
        if isShort {
            // 반 높이: 키 문자와 아이콘만. 이름까지 넣으면 넘친다.
            ZStack {
                glyph.frame(height: 14)
                Text(label)
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isEmpty ? .tertiary : .secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(isEmpty ? .tertiary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                glyph.frame(height: 20)

                Text(caption)
                    .font(.system(size: 7))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.tail)
                    .foregroundStyle(captionColor)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch action {
        case .application(let target):
            if let icon = AppIconProvider.shared.icon(forBundleIdentifier: target.bundleIdentifier) {
                Image(nsImage: icon).resizable()
                    .frame(width: isShort ? 14 : 20, height: isShort ? 14 : 20)
                    .missingAppStyle(!isInstalled, badgeSize: isShort ? 7 : 9)
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .font(.system(size: 14)).foregroundStyle(.red)
            }
        case .media(let command, _):
            Image(systemName: mediaSymbol(for: command))
                .font(.system(size: isShort ? 10 : 13)).foregroundStyle(.secondary)
        case .keyStroke(let stroke):
            Text(stroke.modifiers.map(\.symbol).joined())
                .font(.system(size: 11, weight: .medium))
                .minimumScaleFactor(0.6).lineLimit(1)
                .foregroundStyle(.secondary)
        case .unsupported:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13)).foregroundStyle(.orange)
        case nil:
            Image(systemName: "plus")
                .font(.system(size: isShort ? 9 : 11, weight: .light)).foregroundStyle(.tertiary)
        }
    }

    private var caption: String {
        // 빈 키는 점선 테두리와 + 로 충분하다. 폭에 따라 글자가 있다 없다 하면
        // 어수선하고, 남은 개수는 위쪽 Available 배지가 알려 준다.
        // 설치 안 된 앱도 이름을 그대로 쓴다. 없다는 건 빨간 ? 아이콘과 빨간 글자가
        // 알려 주고, 무슨 앱이 걸려 있었는지는 남아야 다시 깔거나 바꿀 수 있다.
        guard let action else { return "" }
        return shortName(for: action)
    }

    private var captionColor: Color {
        guard let action else { return .secondary.opacity(0.55) }
        if case .application = action, !isInstalled { return .red }
        return .secondary
    }

    private var helpText: String {
        guard let action else { return "비어 있음" }
        switch action {
        case .application(let target):
            return isInstalled
                ? "\(target.displayName) (\(target.bundleIdentifier))"
                : "설치되지 않음: \(target.bundleIdentifier)"
        case .keyStroke(let stroke):
            return "\(stroke.displayName) 를 보냅니다"
        case .media, .unsupported:
            return action.displayName
        }
    }

    private func mediaSymbol(for command: MediaCommand) -> String {
        switch command {
        case .playPause: "playpause.fill"
        case .next: "forward.fill"
        case .previous: "backward.fill"
        }
    }

    /// 앱 이름을 줄이는 휴리스틱은 쓰지 않는다. "Google Chrome" 의 첫 단어를 쓰면
    /// "Google" 이 되고 마지막 단어를 쓰면 "Microsoft Remote Desktop Beta" 가 "Beta" 가
    /// 된다. 어느 쪽도 맞지 않으니 전체 이름을 두 줄까지 쓰고 넘치면 잘리게 둔다.
    private func shortName(for action: ShortcutAction) -> String {
        switch action {
        case .application(let target):
            return target.displayName.isEmpty ? target.bundleIdentifier : target.displayName
        case .media(let command, _):
            switch command {
            case .playPause: return "Play"
            case .next: return "Next"
            case .previous: return "Prev"
            }
        case .keyStroke(let stroke):
            if let label = stroke.label, !label.isEmpty { return label }
            return KeyCodeTable.entry(forIdentifier: stroke.keyIdentifier)?.label
                ?? stroke.keyIdentifier.uppercased()
        case .unsupported:
            return "Unknown"
        }
    }
}

/// 단축키를 걸 수 없는 키. 모양만 그려서 "여기는 쓸 수 없다" 를 보여 준다.
///
/// 그냥 회색으로만 두지 않고, 이 앱이 특별하게 다루는 키에는 무엇이 되는지 적는다.
/// 레이어 트리거는 지금 보는 레이어여도 따로 칠하지 않는다. 파랗게 칠했더니
/// 선택된 키와 똑같아 보여서 헷갈렸다. 지금 레이어는 위쪽 레이어 선택기가 보여 준다.
struct FixedKeycapView: View {

    let key: KeyboardLayout.FixedKey
    let width: CGFloat
    let height: CGFloat
    let config: CapsLockControlConfig

    private var note: String? {
        switch key.role {
        case .modifier:
            return nil
        case .layerTrigger(let layer):
            return layer.shortName
        case .rightCommand:
            return config.rightCommand.action == .f18 ? "→ F18" : nil
        case .fnKey:
            return config.modifiers.swapFnAndLeftControl ? "→ ctrl" : nil
        case .leftControl:
            return config.modifiers.swapFnAndLeftControl ? "→ fn" : nil
        }
    }

    private var tint: Color {
        if case .layerTrigger = key.role { return .secondary }
        return note == nil ? .secondary : .orange
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(key.label)
                .font(.system(size: 9, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(.secondary)
            if let note {
                Text(note)
                    .font(.system(size: 7, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(tint)
            }
        }
        .padding(3)
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.secondary.opacity(0.18)))
        .help(helpText)
    }

    private var helpText: String {
        switch key.role {
        case .modifier: "단축키로 쓸 수 없는 키입니다"
        case .layerTrigger(let layer): "\(layer.displayName) 레이어 트리거"
        case .rightCommand:
            config.rightCommand.action == .f18
                ? "F18 로 바뀝니다 (이전 입력 소스 선택)" : "단축키로 쓸 수 없는 키입니다"
        case .fnKey:
            config.modifiers.swapFnAndLeftControl
                ? "왼쪽 Control 로 동작합니다" : "단축키로 쓸 수 없는 키입니다"
        case .leftControl:
            config.modifiers.swapFnAndLeftControl
                ? "fn 으로 동작합니다" : "단축키로 쓸 수 없는 키입니다"
        }
    }
}

extension View {
    /// 설치되지 않은 앱의 아이콘. 무슨 앱인지는 알아보게 두되, 흑백으로 흐리게 그리고
    /// 빨간 ? 를 붙여서 지금은 실행되지 않는다는 걸 보여 준다.
    func missingAppStyle(_ isMissing: Bool, badgeSize: CGFloat) -> some View {
        saturation(isMissing ? 0 : 1)
            .opacity(isMissing ? 0.45 : 1)
            .overlay(alignment: .bottomTrailing) {
                if isMissing {
                    Image(systemName: "questionmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .font(.system(size: badgeSize, weight: .bold))
                        .offset(x: badgeSize * 0.3, y: badgeSize * 0.3)
                }
            }
    }
}
