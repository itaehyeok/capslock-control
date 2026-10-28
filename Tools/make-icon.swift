import AppKit

// CapsLockControl 앱 아이콘 생성기.
//
// 핵심은 **크기별로 디테일을 줄이는 것**이다. 512px 에서 예쁜 그림을 그대로 16px 로
// 줄이면 얼룩이 된다. 그래서 작은 크기에서는 글자를 빼고 불을 키운다.
//
// 그림: 어두운 스퀘어클 위에 스페이스 그레이 Caps Lock 키 하나. 왼쪽 위에 초록 불이
// 켜져 있고, 큰 크기에서만 "caps lock" 글자를 새긴다(128px 아래에서는 읽히지 않는다).
//
// 좌표는 시안을 그린 단위 그대로다. 바탕(스퀘어클) 한 변을 84 로 보고 왼쪽 위에서 잰다.

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outputPath, withIntermediateDirectories: true)

extension NSBezierPath {
    static func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
}

private let backgroundTop = NSColor(srgbRed: 0.14, green: 0.15, blue: 0.18, alpha: 1)
private let backgroundBottom = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1)
private let keyShadowColor = NSColor(srgbRed: 0.04, green: 0.05, blue: 0.06, alpha: 1)
private let keyColor = NSColor(srgbRed: 0.20, green: 0.21, blue: 0.24, alpha: 1)
private let ledColor = NSColor(srgbRed: 0.36, green: 0.94, blue: 0.54, alpha: 1)
private let ledGlowColor = NSColor(srgbRed: 0.24, green: 0.86, blue: 0.42, alpha: 0.25)
private let legendColor = NSColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1)

/// 크기마다 무엇을 그릴지.
private enum Detail {
    /// 128px 이상. 글자까지 새긴다.
    case full
    /// 32~127px. 글자를 빼고 불을 키운다.
    case medium
    /// 32px 미만. 키와 불만. 불은 최소 크기를 지켜 점으로라도 남긴다.
    case tiny

    init(pixels: Int) {
        switch pixels {
        case ..<32: self = .tiny
        case ..<128: self = .medium
        default: self = .full
        }
    }
}

private func render(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let side = CGFloat(pixels)
    let detail = Detail(pixels: pixels)
    // macOS 아이콘은 사방에 여백이 있다. 1024 기준 100px.
    let inset = side * 0.0977
    let body = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let bodyRadius = side * 0.1855
    let unit = body.width / 84

    /// 시안 좌표(왼쪽 위 기준) → 그림 좌표(왼쪽 아래 기준).
    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: body.minX + x * unit, y: body.maxY - (y + height) * unit,
               width: width * unit, height: height * unit)
    }
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: body.minX + x * unit, y: body.maxY - y * unit)
    }

    // 1) 바탕
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath.rounded(body, bodyRadius).addClip()
    NSGradient(colors: [backgroundTop, backgroundBottom])?.draw(in: body, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // 2) 키. 아래로 비친 어두운 옆면을 먼저 깔고 윗면을 얹는다.
    keyShadowColor.setFill()
    NSBezierPath.rounded(rect(7, 23, 70, 44), 9 * unit).fill()
    keyColor.setFill()
    NSBezierPath.rounded(rect(7, 19, 70, 43), 9 * unit).fill()

    // 3) 초록 불. 작아질수록 상대적으로 키워야 불로 보인다.
    let ledCenter = point(16, 28)
    let ledRadius: CGFloat = switch detail {
    case .full: 3 * unit
    case .medium: 4.5 * unit
    case .tiny: max(1.2, 4.5 * unit)
    }
    if detail != .tiny {
        let glow = ledRadius * 2
        ledGlowColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: ledCenter.x - glow, y: ledCenter.y - glow,
                                    width: glow * 2, height: glow * 2)).fill()
    }
    ledColor.setFill()
    NSBezierPath(ovalIn: NSRect(x: ledCenter.x - ledRadius, y: ledCenter.y - ledRadius,
                                width: ledRadius * 2, height: ledRadius * 2)).fill()

    // 4) 글자. 큰 크기에서만.
    if detail == .full {
        let font = NSFont.systemFont(ofSize: 11.5 * unit, weight: .regular)
        let legend = NSAttributedString(string: "caps lock",
                                        attributes: [.font: font, .foregroundColor: legendColor])
        // draw(at:) 의 기준은 글자 상자 왼쪽 아래다. 기준선을 맞추려고 descender 만큼 내린다.
        let baseline = point(14, 54)
        legend.draw(at: NSPoint(x: baseline.x, y: baseline.y + font.descender))
    }

    return rep.representation(using: .png, properties: [:])
}

let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, pixels) in entries {
    guard let data = render(pixels: pixels) else {
        FileHandle.standardError.write(Data("\(name) 렌더 실패\n".utf8))
        exit(1)
    }
    try data.write(to: URL(fileURLWithPath: outputPath).appendingPathComponent("\(name).png"))
}
print("생성 완료: \(outputPath)")
