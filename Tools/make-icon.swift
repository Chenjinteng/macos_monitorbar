// 生成 MonitorBar.app 的图标（.iconset → .icns）
// 用法: swift Tools/make-icon.swift <输出 .iconset 目录>
import AppKit
import Foundation

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./build/MonitorBar.iconset"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func makeImage(pixels: Int) -> NSImage {
    let s = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    defer { image.unlockFocus() }

    // ---------- 底板：连续曲率圆角矩形 ----------
    let inset = s * 0.08
    let side = s - inset * 2
    let body = NSRect(x: inset, y: inset, width: side, height: side)
    let cornerRadius = side * 0.235
    let plate = NSBezierPath(roundedRect: body, xRadius: cornerRadius, yRadius: cornerRadius)

    // 主渐变：靛蓝 → 青
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.31, green: 0.27, blue: 0.90, alpha: 1),   // #4F46E5 indigo
        NSColor(srgbRed: 0.02, green: 0.71, blue: 0.83, alpha: 1)    // #06B6D4 cyan
    ])
    gradient?.draw(in: plate, angle: -45)

    // 顶部高光：让图标有立体感而不是纯平面
    NSGraphicsContext.saveGraphicsState()
    plate.addClip()
    let highlight = NSRect(x: inset, y: s - inset - side * 0.55,
                           width: side, height: side * 0.55)
    NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10).setFill()
    NSBezierPath(rect: highlight).fill()
    NSGraphicsContext.restoreGraphicsState()

    // ---------- 仪表盘：粗白环 + 已用弧 + 末端亮点 ----------
    let ringCenter = NSPoint(x: s / 2, y: s / 2 + s * 0.05)
    let ringRadius = side * 0.28
    let lineWidth = side * 0.095
    let startAngle: CGFloat = 135
    let totalSpan: CGFloat = 270
    let usedRatio: CGFloat = 0.68

    // 暗底环
    NSColor(white: 1, alpha: 0.22).setStroke()
    let base = NSBezierPath()
    base.appendArc(withCenter: ringCenter, radius: ringRadius,
                   startAngle: startAngle, endAngle: startAngle + totalSpan)
    base.lineWidth = lineWidth
    base.lineCapStyle = .round
    base.stroke()

    // 已用弧（亮白）
    let usedEnd = startAngle + totalSpan * usedRatio
    let used = NSBezierPath()
    used.appendArc(withCenter: ringCenter, radius: ringRadius,
                   startAngle: startAngle, endAngle: usedEnd)
    used.lineWidth = lineWidth
    used.lineCapStyle = .round
    NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.98).setStroke()
    used.stroke()

    // 末端亮绿小圆点
    let tipAngle = usedEnd * .pi / 180
    let tipX = ringCenter.x + ringRadius * cos(tipAngle)
    let tipY = ringCenter.y + ringRadius * sin(tipAngle)
    let dotR = lineWidth * 0.55
    let dot = NSBezierPath(ovalIn: NSRect(
        x: tipX - dotR, y: tipY - dotR, width: dotR * 2, height: dotR * 2
    ))
    NSColor(srgbRed: 0.55, green: 1.00, blue: 0.72, alpha: 1).setFill()
    dot.fill()

    // ---------- 内存条堆叠：环下方三段递减 ----------
    let barH = lineWidth * 0.48
    let barGap = barH * 0.75
    let widths: [CGFloat] = [0.88, 0.60, 0.34]
    let maxBarW = side * 0.34
    let startX = s / 2 - maxBarW / 2
    let baseY = ringCenter.y - ringRadius - side * 0.10
    for (i, r) in widths.enumerated() {
        let w = maxBarW * r
        let y = baseY - CGFloat(widths.count - 1 - i) * (barH + barGap)
        let rect = NSRect(x: startX, y: y, width: w, height: barH)
        let bar = NSBezierPath(roundedRect: rect, xRadius: barH / 2, yRadius: barH / 2)
        NSColor(white: 1, alpha: 1 - Double(i) * 0.32).setFill()
        bar.fill()
    }

    return image
}

func png(from image: NSImage, pixels: Int) -> Data? {
    let out = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    out.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
               from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return out.representation(using: .png, properties: [:])
}

let variants: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]

for (px, name) in variants {
    let image = makeImage(pixels: px)
    guard let data = png(from: image, pixels: px) else { continue }
    try? data.write(to: URL(fileURLWithPath: "\(outputDir)/\(name)"))
}

print("iconset 已生成: \(outputDir)")
