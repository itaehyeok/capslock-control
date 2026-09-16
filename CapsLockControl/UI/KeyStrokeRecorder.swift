import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 보낼 키 조합을 눌러서 지정하는 칸.
///
/// 클릭하면 녹화가 시작되고 다음에 누르는 조합을 그대로 받는다.
/// esc 는 취소, delete 는 지우기다.
///
/// SwiftUI 대신 NSView 로 만든 이유는 `event.keyCode` 가 필요하기 때문이다.
/// 문자로 받으면 ⌥+a 가 "å" 로 오는 등 자판 배열에 휘둘린다. keyCode 는 자리를
/// 가리키므로 한글 입력 중이어도 같은 값이 온다.
struct KeyStrokeRecorder: NSViewRepresentable {

    var stroke: KeyStroke?
    /// nil 이면 지우기.
    var onRecord: (KeyStroke?) -> Void

    func makeNSView(context: Context) -> KeyStrokeRecorderNSView {
        let view = KeyStrokeRecorderNSView()
        view.stroke = stroke
        view.onRecord = onRecord
        return view
    }

    func updateNSView(_ nsView: KeyStrokeRecorderNSView, context: Context) {
        nsView.stroke = stroke
        nsView.onRecord = onRecord
    }
}

final class KeyStrokeRecorderNSView: NSView {

    var onRecord: ((KeyStroke?) -> Void)?

    var stroke: KeyStroke? {
        didSet { needsDisplay = true }
    }

    private var isRecording = false {
        didSet { needsDisplay = true }
    }

    /// 녹화 중 지금 누르고 있는 수정자. 미리보기로만 쓴다.
    private var liveModifiers: NSEvent.ModifierFlags = [] {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 200, height: 26) }
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    // MARK: - 입력

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording.toggle()
        liveModifiers = []
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        liveModifiers = []
        return super.resignFirstResponder()
    }

    /// 수정자가 붙은 조합은 keyDown 보다 먼저 이쪽으로 온다.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        return handle(event)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording, handle(event) else {
            super.keyDown(with: event)
            return
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        liveModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }

    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == UInt16(kVK_Escape), modifiers(from: flags).isEmpty {
            isRecording = false
            liveModifiers = []
            return true
        }
        if event.keyCode == UInt16(kVK_Delete), modifiers(from: flags).isEmpty {
            stroke = nil
            isRecording = false
            liveModifiers = []
            onRecord?(nil)
            return true
        }
        // 우리 키 표에 없는 키(F1 등)는 받지 않는다. 보낼 수 없기 때문이다.
        guard let identifier = KeyCodeTable.identifier(for: KeyCode(CGKeyCode(event.keyCode))) else {
            NSSound.beep()
            return true
        }
        let recorded = KeyStroke(keyIdentifier: identifier, modifiers: modifiers(from: flags))
        stroke = recorded
        isRecording = false
        liveModifiers = []
        onRecord?(recorded)
        return true
    }

    private func modifiers(from flags: NSEvent.ModifierFlags) -> [KeyStrokeModifier] {
        var result: [KeyStrokeModifier] = []
        if flags.contains(.control) { result.append(.control) }
        if flags.contains(.option) { result.append(.option) }
        if flags.contains(.shift) { result.append(.shift) }
        if flags.contains(.command) { result.append(.command) }
        return result
    }

    // MARK: - 그리기

    override func draw(_ dirtyRect: NSRect) {
        let rounded = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                   xRadius: 5, yRadius: 5)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12)
                     : NSColor.textBackgroundColor).setFill()
        rounded.fill()
        (isRecording ? NSColor.controlAccentColor
                     : NSColor.separatorColor).setStroke()
        rounded.lineWidth = isRecording ? 2 : 1
        rounded.stroke()

        let text = displayText
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: isRecording || stroke == nil
                ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(x: (bounds.width - size.width) / 2,
                             y: (bounds.height - size.height) / 2)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    private var displayText: String {
        guard isRecording else { return stroke?.comboString ?? "지정되지 않음" }
        let preview = modifiers(from: liveModifiers).map(\.symbol).joined()
        return preview.isEmpty ? "조합을 누르세요" : preview
    }
}
