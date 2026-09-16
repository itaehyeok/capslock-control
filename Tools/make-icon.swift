import AppKit

// CapsLockControl 앱 아이콘 생성기.
//
// 핵심은 **크기별로 디테일을 줄이는 것**이다. 512px 에서 예쁜 그림을 그대로 16px 로
// 줄이면 얼룩이 된다. 그래서 작은 크기에서는 키 개수를 줄이고 선을 굵게 잡는다.
//
// 그림: 어두운 스퀘어클 위에 흰 키보드 판, 그 위에 어두운 키들을 파낸다.
// 왼쪽 아래 키 하나만 파란색 — 그게 "레이어 키" 다. 16px 에서도 색으로 구분된다.

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outputPath, withIntermediateDirectories: true)

extension NSBezierPath {
    static func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
}

private let backgroundTop = NSColor(srgbRed: 0.20, green: 0.23, blue: 0.32, alpha: 1)
private let backgroundBottom = NSColor(srgbRed: 0.055, green: 0.07, blue: 0.11, alpha: 1)
private let plateColor = NSColor(srgbRed: 0.96, green: 0.97, blue: 0.99, alpha: 1)
private let keyColor = NSColor(srgbRed: 0.11, green: 0.13, blue: 0.19, alpha: 1)
private let accentColor = NSColor(srgbRed: 0.30, green: 0.55, blue: 1.0, alpha: 1)

/// 크기에 따라 몇 개의 키를 그릴지. 작을수록 크고 적게.
private func keysPerRow(for pixels: Int) -> Int {
    switch pixels {
    case ..<24: 3
    case ..<48: 4
    case ..<128: 5
    default: 6
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
    // macOS 아이콘은 사방에 여백이 있다. 1024 기준 100px.
    let inset = side * 0.0977
    let body = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let bodyRadius = side * 0.1855

    // 1) 바탕
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath.rounded(body, bodyRadius).addClip()
    NSGradient(colors: [backgroundTop, backgroundBottom])?.draw(in: body, angle: -90)
    // 위쪽 유리 반사. 밋밋함을 덜어 준다.
    NSGradient(colors: [NSColor(white: 1, alpha: 0.13), NSColor(white: 1, alpha: 0)])?
        .draw(in: NSRect(x: body.minX, y: body.midY,
                         width: body.width, height: body.height * 0.5), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // 2) 흰 키보드 판. 실루엣이 굵어야 작은 크기에서 산다.
    let plateWidth = body.width * 0.70
    let plateHeight = plateWidth * 0.60
    let plate = NSRect(x: body.midX - plateWidth / 2,
                       y: body.midY - plateHeight / 2,
                       width: plateWidth, height: plateHeight)
    let plateRadius = max(1, plateHeight * 0.17)
    plateColor.setFill()
    NSBezierPath.rounded(plate, plateRadius).fill()

    // 3) 키를 어두운 색으로 파낸다.
    let columns = keysPerRow(for: pixels)
    let padding = plateHeight * 0.15
    let inner = plate.insetBy(dx: padding, dy: padding)
    let gap = max(pixels <= 32 ? 1 : 1.5, inner.width * 0.035)
    let keyWidth = (inner.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
    // 위 두 줄 + 스페이스 한 줄
    let keyHeight = (inner.height - gap * 2) / 3
    let keyRadius = max(0.5, keyHeight * 0.25)

    for row in 0..<2 {
        // y 는 위에서부터. NSRect 는 아래가 0 이므로 뒤집어 계산한다.
        let y = inner.maxY - keyHeight * CGFloat(row + 1) - gap * CGFloat(row)
        for column in 0..<columns {
            let x = inner.minX + (keyWidth + gap) * CGFloat(column)
            let key = NSRect(x: x, y: y, width: keyWidth, height: keyHeight)
            // 둘째 줄 맨 왼쪽이 레이어 키(Caps Lock 자리).
            let isLayerKey = (row == 1 && column == 0)
            (isLayerKey ? accentColor : keyColor).setFill()
            NSBezierPath.rounded(key, keyRadius).fill()
        }
    }

    // 스페이스 바
    let spaceInset = keyWidth + gap
    let space = NSRect(x: inner.minX + spaceInset, y: inner.minY,
                       width: inner.width - spaceInset * 2, height: keyHeight)
    if space.width > 0 {
        keyColor.setFill()
        NSBezierPath.rounded(space, keyRadius).fill()
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
