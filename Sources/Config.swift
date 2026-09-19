import Foundation

// MARK: - 路径
//
// 沙盒扩展里 NSHomeDirectory() / homeDirectoryForCurrentUser 拿到的是容器路径
// （…/Containers/<id>/Data），不是真实主目录。必须用 getpwuid。
// 上一版扩展就是读容器里的空配置，导致主 App 的开关全部失效。

enum AppPaths {
    static var realHome: URL {
        if let pw = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var support: URL {
        realHome.appendingPathComponent("Library/Application Support/SuperRightClick")
    }

    static var configFile: URL { support.appendingPathComponent("config.json") }
    static var diagFile: URL { support.appendingPathComponent("diag.log") }
    static var lastInfoFile: URL { support.appendingPathComponent("last-info.txt") }

    /// 主 App 的 bundle（扩展在它内部的 PlugIns 里）。
    static var hostApp: URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

/// 诊断日志，主 App 和扩展写同一个文件，出问题直接 cat。
func diag(_ message: String) {
    let line = "[\(Date())] \(message)\n"
    try? FileManager.default.createDirectory(at: AppPaths.support, withIntermediateDirectories: true)
    if let handle = try? FileHandle(forWritingTo: AppPaths.diagFile) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8) ?? Data())
        try? handle.close()
    } else {
        try? line.write(to: AppPaths.diagFile, atomically: true, encoding: .utf8)
    }
}

// MARK: - 应用标识

enum AppInfo {
    /// 显示名称。右键菜单只出现这一个入口，所有功能都收在它的子菜单里。
    static let name = "右键伴侣"
}

// MARK: - 配置模型

struct FileType: Codable, Equatable, Identifiable {
    var id: UUID
    var displayName: String
    var ext: String
    var enabled: Bool
    var template: String?

    init(id: UUID = UUID(), displayName: String, ext: String, enabled: Bool,
         template: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.ext = ext
        self.enabled = enabled
        self.template = template
    }

    enum CodingKeys: String, CodingKey {
        case id, displayName, ext, enabled, template
    }

    /// 老配置里没有 id。容忍缺失并补一个，否则升级会把用户配置整个打回默认。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        displayName = try container.decode(String.self, forKey: .displayName)
        ext = try container.decode(String.self, forKey: .ext)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        template = try container.decodeIfPresent(String.self, forKey: .template)
    }
}

struct Shortcut: Codable, Equatable, Identifiable {
    var id: UUID
    var displayName: String
    var path: String
    var enabled: Bool

    init(id: UUID = UUID(), displayName: String, path: String, enabled: Bool) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey {
        case id, displayName, path, enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        displayName = try container.decode(String.self, forKey: .displayName)
        path = try container.decode(String.self, forKey: .path)
        enabled = try container.decode(Bool.self, forKey: .enabled)
    }
}

/// 工具箱的功能键。显示名称放在设置界面里，扩展只认键。
enum ToolKey {
    static let all: [(key: String, title: String)] = [
        ("copyPath", "复制路径"),
        ("copyName", "拷贝文件（夹）名称"),
        ("newFolderByName", "用文件名新建文件夹"),
        ("cut", "剪切"),
        ("dissolveFolder", "解散文件夹"),
        ("deletePermanently", "彻底删除（不进废纸篓）"),
        ("toggleHidden", "隐藏 / 显示文件"),
        ("grantWrite", "授予选择的文件写入权限"),
        ("shortcutOnDesktop", "发送快捷方式到桌面"),
        ("fileInfo", "文件信息（大小 / MD5 / SHA256）"),
        ("openInTerminal", "在终端中打开"),
    ]

    /// 图片相关功能。单独分组：它们只在选中图片时才出现，跟上面的通用工具有本质区别。
    static let image: [(key: String, title: String)] = [
        ("imageConvert", "转格式（PNG / JPG / HEIC / TIFF）"),
        ("imageIconSet", "生成 macOS / iOS 图标集"),
        ("imageICNS", "生成 ICNS"),
        ("imageWallpaper", "设为墙纸"),
    ]

    static var everyKey: [String] { (all + image).map(\.key) }
}

struct AppConfig: Codable, Equatable {
    var showMenuBarIcon: Bool
    var showIconsInMenu: Bool
    var soundEnabled: Bool
    var openAfterCreate: Bool
    var terminalApp: String
    var sendMove: Bool
    var fileTypes: [FileType]
    var commonDirectories: [Shortcut]
    var sendToDirectories: [Shortcut]
    var tools: [String: Bool]
    var pendingCut: [String]

    func tool(_ key: String) -> Bool { tokens(key) }

    private func tokens(_ key: String) -> Bool { tools[key] ?? true }

    static var standard: AppConfig {
        let home = AppPaths.realHome
        return AppConfig(
            showMenuBarIcon: true,
            showIconsInMenu: true,
            soundEnabled: true,
            openAfterCreate: false,
            terminalApp: "/System/Applications/Utilities/Terminal.app",
            sendMove: false,
            fileTypes: [
                FileType(displayName: "纯文本", ext: "txt", enabled: true, template: nil),
                FileType(displayName: "Markdown", ext: "md", enabled: true, template: nil),
                FileType(displayName: "富文本", ext: "rtf", enabled: true, template: nil),
                FileType(displayName: "JSON", ext: "json", enabled: true, template: nil),
                FileType(displayName: "HTML", ext: "html", enabled: true, template: nil),
                FileType(displayName: "XML", ext: "xml", enabled: true, template: nil),
                FileType(displayName: "Word", ext: "docx", enabled: true, template: nil),
                FileType(displayName: "Excel", ext: "xlsx", enabled: true, template: nil),
                FileType(displayName: "PPT", ext: "pptx", enabled: true, template: nil),
                FileType(displayName: "WPS 文字", ext: "wps", enabled: true, template: nil),
                FileType(displayName: "WPS 表格", ext: "et", enabled: true, template: nil),
                FileType(displayName: "WPS 演示", ext: "dps", enabled: true, template: nil),
                FileType(displayName: "Pages", ext: "pages", enabled: false, template: nil),
                FileType(displayName: "Numbers", ext: "numbers", enabled: false, template: nil),
                FileType(displayName: "Keynote", ext: "key", enabled: false, template: nil),
                FileType(displayName: "Illustrator", ext: "ai", enabled: false, template: nil),
                FileType(displayName: "Photoshop", ext: "psd", enabled: false, template: nil),
            ],
            commonDirectories: [
                Shortcut(displayName: "桌面", path: home.appendingPathComponent("Desktop").path, enabled: true),
                Shortcut(displayName: "文稿", path: home.appendingPathComponent("Documents").path, enabled: true),
                Shortcut(displayName: "下载", path: home.appendingPathComponent("Downloads").path, enabled: true),
            ],
            sendToDirectories: [
                Shortcut(displayName: "下载", path: home.appendingPathComponent("Downloads").path, enabled: true),
                Shortcut(displayName: "图片", path: home.appendingPathComponent("Pictures").path, enabled: true),
                Shortcut(displayName: "音乐", path: home.appendingPathComponent("Music").path, enabled: true),
                Shortcut(displayName: "影片", path: home.appendingPathComponent("Movies").path, enabled: true),
                Shortcut(displayName: "文稿", path: home.appendingPathComponent("Documents").path, enabled: true),
            ],
            tools: Dictionary(uniqueKeysWithValues: ToolKey.everyKey.map { ($0, true) }),
            pendingCut: []
        )
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: AppPaths.configFile),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            diag("配置不存在或解析失败，用默认配置")
            return .standard
        }
        return config
    }

    func save() {
        try? FileManager.default.createDirectory(at: AppPaths.support, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        // 原子写：扩展可能正好在读，非原子写会让它读到半个文件
        try? data.write(to: AppPaths.configFile, options: .atomic)
    }
}
