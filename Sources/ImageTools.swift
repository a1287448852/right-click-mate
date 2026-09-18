import Cocoa
import ImageIO
import UniformTypeIdentifiers

/// 图片处理工具。对照 iRightMouse 的图片能力：
/// 转格式（PNG / JPG / HEIC / TIFF）、生成 ICNS、生成 macOS / iOS 图标集、设为墙纸。
///
/// 全部走 ImageIO，不引第三方库。生成的产物放在源文件同目录。
enum ImageTools {

    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp", "icns", "psd",
    ]

    static func isImage(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// macOS 图标集需要的文件名与像素尺寸（iconutil 认这套命名）
    private static let macIconVariants: [(String, Int)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]

    /// iOS 图标集（iPhone / iPad 常用尺寸）
    private static let iosIconVariants: [(String, Int)] = [
        ("Icon-20@2x.png", 40), ("Icon-20@3x.png", 60),
        ("Icon-29@2x.png", 58), ("Icon-29@3x.png", 87),
        ("Icon-40@2x.png", 80), ("Icon-40@3x.png", 120),
        ("Icon-60@2x.png", 120), ("Icon-60@3x.png", 180),
        ("Icon-76@2x.png", 152), ("Icon-83.5@2x.png", 167),
        ("Icon-1024.png", 1024),
    ]

    // MARK: - 转格式

    @discardableResult
    static func convert(_ url: URL, to type: UTType) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let base = url.deletingPathExtension().lastPathComponent
        let ext = type.preferredFilenameExtension ?? "img"
        // 已经是这个格式就别转了，否则会生成 "xxx 2.png" 这种废文件
        guard url.pathExtension.lowercased() != ext else { return nil }
        let target = uniqueURL(in: url.deletingLastPathComponent(), name: "\(base).\(ext)")

        guard let destination = CGImageDestinationCreateWithURL(
            target as CFURL, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return target
    }

    // MARK: - ICNS

    @discardableResult
    static func makeICNS(_ url: URL) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let base = url.deletingPathExtension().lastPathComponent
        let target = uniqueURL(in: url.deletingLastPathComponent(), name: "\(base).icns")

        // icns 里要装多个尺寸，从 16 到 1024
        let sizes = [16, 32, 64, 128, 256, 512, 1024]
        guard let destination = CGImageDestinationCreateWithURL(
            target as CFURL, UTType.icns.identifier as CFString, sizes.count, nil) else { return nil }

        for size in sizes {
            guard let image = render(source, pixels: size) else { continue }
            CGImageDestinationAddImage(destination, image, nil)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return target
    }

    // MARK: - 图标集

    @discardableResult
    static func makeIconSet(_ url: URL, iOS: Bool) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let base = url.deletingPathExtension().lastPathComponent
        let folderName = iOS ? "\(base).appiconset" : "\(base).iconset"
        let folder = uniqueURL(in: url.deletingLastPathComponent(), name: folderName)

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        } catch {
            diag("图标集目录创建失败：\(error.localizedDescription)")
            return nil
        }

        var written = 0
        for (name, pixels) in (iOS ? iosIconVariants : macIconVariants) {
            guard let image = render(source, pixels: pixels),
                  let data = pngData(image) else { continue }
            let file = folder.appendingPathComponent(name)
            if (try? data.write(to: file)) != nil { written += 1 }
        }

        guard written > 0 else {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
        diag("图标集生成 \(written)/\(( iOS ? iosIconVariants : macIconVariants).count) 张 → \(folder.path)")
        return folder
    }

    // MARK: - 墙纸

    @discardableResult
    static func setAsWallpaper(_ url: URL) -> Bool {
        guard let screen = NSScreen.main else { return false }
        do {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            return true
        } catch {
            diag("设置墙纸失败：\(error.localizedDescription)")
            return false
        }
    }

    // MARK: - 内部

    /// 画到精确的像素尺寸。
    ///
    /// 不能用 CGImageSourceCreateThumbnailAtIndex：它只会缩不会放，
    /// 源图 512px 时所有 ≥512 的尺寸都会停在 512，生成的图标集是残缺的，
    /// iconutil 会直接拒绝。
    private static func render(_ source: CGImageSource, pixels: Int) -> CGImage? {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        guard let context = CGContext(data: nil, width: pixels, height: pixels,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage()
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func uniqueURL(in directory: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var url = directory.appendingPathComponent(name)
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent(ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)")
            index += 1
        }
        return url
    }
}
