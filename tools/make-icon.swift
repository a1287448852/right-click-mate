// 生成 App 图标。
//
// 没有 Xcode / Icon Composer，用 CoreGraphics 直接画，再用 iconutil 打包成 .icns。
// 视觉遵循 Pinguo 设计系统：品牌蓝渐变 + 玻璃高光 + 内侧描边，中间是白色光标。
//
// 用法：swift tools/make-icon.swift <输出目录>

import Cocoa

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

/// macOS 图标的圆角比例约 22.37%
private let cornerRatio: CGFloat = 0.2237

/// 光标轮廓，归一化到 0…1 的方框（y 轴向上）
private func cursorPath(in box: NSRect) -> NSBezierPath {
    let points: [(CGFloat, CGFloat)] = [
        (0.00, 1.00),   // 尖端
        (0.00, 0.28),   // 左边垂直下来
        (0.30, 0.44),   // 内侧缺口
        (0.52, 0.00),   // 尾巴底端
        (0.72, 0.09),   // 尾巴右下
        (0.52, 0.49),   // 回到缺口
        (0.86, 0.49),   // 箭头右角
    ]
    let path = NSBezierPath()
    for (index, point) in points.enumerated() {
        let scaled = NSPoint(x: box.minX + point.0 * box.width, y: box.minY + point.1 * box.height)
        if index == 0 { path.move(to: scaled) } else { path.line(to: scaled) }
    }
    path.close()
    return path
}

private func drawIcon(in rect: NSRect) {
    let inset = rect.width * 0.085
    let art = rect.insetBy(dx: inset, dy: inset)
    let radius = art.width * cornerRatio
    let squircle = NSBezierPath(roundedRect: art, xRadius: radius, yRadius: radius)

    // 1. 品牌蓝渐变
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.18, green: 0.55, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.00, green: 0.31, blue: 0.68, alpha: 1),
    ])
    gradient?.draw(in: squircle, angle: -90)

    // 2. 玻璃三件套：顶部受光 + 斜向镜面 + 底部内阴影
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()

    let highlight = NSGradient(colors: [
        NSColor(white: 1, alpha: 0.40),
        NSColor(white: 1, alpha: 0.00),
    ])
    highlight?.draw(in: NSRect(x: art.minX, y: art.midY, width: art.width, height: art.height / 2), angle: -90)

    let sheen = NSBezierPath()
    let width = art.width
    sheen.move(to: NSPoint(x: art.minX, y: art.minY + width * 0.34))
    sheen.line(to: NSPoint(x: art.minX + width * 0.34, y: art.minY))
    sheen.line(to: NSPoint(x: art.minX + width * 0.68, y: art.minY))
    sheen.line(to: NSPoint(x: art.minX, y: art.minY + width * 0.68))
    sheen.close()
    NSGradient(colors: [
        NSColor(white: 1, alpha: 0.00),
        NSColor(white: 1, alpha: 0.20),
        NSColor(white: 1, alpha: 0.00),
    ])?.draw(in: sheen, angle: -40)

    NSGradient(colors: [
        NSColor(white: 0, alpha: 0.16),
        NSColor(white: 0, alpha: 0.00),
    ])?.draw(in: NSRect(x: art.minX, y: art.minY, width: art.width, height: art.height * 0.32), angle: 90)

    NSGraphicsContext.restoreGraphicsState()
    let border = NSBezierPath(roundedRect: art.insetBy(dx: art.width * 0.006, dy: art.width * 0.006),
                              xRadius: radius * 0.99, yRadius: radius * 0.99)
    border.lineWidth = max(1, art.width * 0.007)
    NSColor(white: 1, alpha: 0.28).setStroke()
    border.stroke()

    // 5. 白色光标
    let cursorBox = NSRect(x: art.midX - art.width * 0.27,
                           y: art.midY - art.height * 0.27,
                           width: art.width * 0.50,
                           height: art.height * 0.52)
    let cursor = cursorPath(in: cursorBox)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.30)
    shadow.shadowBlurRadius = art.width * 0.035
    shadow.shadowOffset = NSSize(width: 0, height: -art.width * 0.014)
    shadow.set()
    NSColor.white.setFill()
    cursor.fill()
    NSGraphicsContext.restoreGraphicsState()
}

private func render(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        return nil
    }
    rep.size = NSSize(width: pixels, height: pixels)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    drawIcon(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// iconutil 要求的文件名与像素尺寸
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, pixels) in variants {
    guard let data = render(pixels: pixels) else {
        FileHandle.standardError.write("渲染失败：\(name)\n".data(using: .utf8)!)
        exit(1)
    }
    let path = (outputDirectory as NSString).appendingPathComponent(name)
    try? data.write(to: URL(fileURLWithPath: path))
}

print("图标已生成到 \(outputDirectory)")
