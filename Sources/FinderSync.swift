import Cocoa
import FinderSync
import CryptoKit
import UniformTypeIdentifiers

class FinderSync: FIFinderSync {

    /// 配置缓存。菜单是热路径，每次都读盘 + 解析 JSON 没必要。
    /// 用文件修改时间做失效判断，主 App 一改就会变。
    private var cachedConfig: AppConfig?
    private var cachedStamp: Date?

    /// 图标缓存。NSWorkspace.icon(forFileType:) 是同步查图标数据库，
    /// 12 种格式就是 12 次，弹菜单会明显卡。
    private static var iconCache: [String: NSImage] = [:]

    override init() {
        super.init()
        // init 里不要做任何文件 I/O：Finder 会回收空闲的扩展进程，
        // 用户下次右键时要等这个进程重新起来，init 越重第一下越慢。
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override var toolbarItemName: String { AppInfo.name }
    override var toolbarItemToolTip: String { AppInfo.name }
    override var toolbarItemImage: NSImage {
        NSImage(named: NSImage.touchBarOpenInBrowserTemplateName) ?? NSImage()
    }

    // MARK: - 缓存

    private func currentConfig() -> AppConfig {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: AppPaths.configFile.path))?[.modificationDate] as? Date
        if let cachedConfig, cachedStamp == stamp { return cachedConfig }
        let config = AppConfig.load()
        cachedConfig = config
        cachedStamp = stamp
        return config
    }

    private static func icon(for ext: String) -> NSImage? {
        if let cached = iconCache[ext] { return cached }
        // icon(forFileType:) 从 macOS 12 起就废弃了，换成基于 UTType 的新接口
        guard let type = UTType(filenameExtension: ext) else { return nil }
        let image = NSWorkspace.shared.icon(for: type)
        image.size = NSSize(width: 16, height: 16)
        iconCache[ext] = image
        return image
    }

    // MARK: - 菜单
    //
    // Finder 会把扩展返回的菜单项平铺进右键菜单，所以这里只返回一项：
    // 一个名叫「右键伴侣」的父项，所有功能都塞进它的子菜单。

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems
                || menuKind == .contextualMenuForContainer
                || menuKind == .contextualMenuForSidebar else { return nil }

        let started = Date()
        let config = currentConfig()
        let selection = selectedURLs
        let content = NSMenu(title: AppInfo.name)
        buildContent(into: content, config: config, selection: selection,
                     sidebar: menuKind == .contextualMenuForSidebar)

        guard content.numberOfItems > 0 else { return nil }
        let parent = NSMenuItem(title: AppInfo.name, action: nil, keyEquivalent: "")
        parent.submenu = content

        let root = NSMenu(title: "")
        root.addItem(parent)

        let elapsed = Date().timeIntervalSince(started) * 1000
        diag("menu 构建 \(Int(elapsed))ms，子菜单 \(content.numberOfItems) 项，选中 \(selection.count)")
        return root
    }

    private func buildContent(into menu: NSMenu, config: AppConfig, selection: [URL], sidebar: Bool) {
        let hasSelection = !selection.isEmpty

        if !sidebar {
            addNewFileItems(to: menu, config: config)
        }

        if hasSelection && !sidebar {
            menu.addItem(.separator())
            if config.tool("copyPath") { menu.addItem(item("复制路径", #selector(copyPath(_:)))) }
            if config.tool("copyName") { menu.addItem(item("复制文件名", #selector(copyName(_:)))) }
            if config.tool("newFolderByName") { menu.addItem(item("用文件名新建文件夹", #selector(newFolderByName(_:)))) }
            if config.tool("cut") { menu.addItem(item("剪切", #selector(cut(_:)))) }
        }
        if !config.pendingCut.isEmpty {
            menu.addItem(item("粘贴到此处（移动 \(config.pendingCut.count) 项）", #selector(pasteMove(_:))))
        }

        menu.addItem(.separator())
        addDestinationMenus(to: menu, config: config)

        if hasSelection && !sidebar {
            menu.addItem(.separator())
            if config.tool("fileInfo") { menu.addItem(item("文件信息", #selector(fileInfo(_:)))) }
            if config.tool("dissolveFolder") { menu.addItem(item("解散文件夹", #selector(dissolveFolder(_:)))) }
            if config.tool("toggleHidden") { menu.addItem(item("隐藏 / 显示", #selector(toggleHidden(_:)))) }
            if config.tool("grantWrite") { menu.addItem(item("授予写入权限", #selector(grantWrite(_:)))) }
            if config.tool("shortcutOnDesktop") { menu.addItem(item("发送快捷方式到桌面", #selector(shortcutOnDesktop(_:)))) }
            if config.tool("deletePermanently") { menu.addItem(item("彻底删除（不进废纸篓）", #selector(deletePermanently(_:)))) }
        }

        if hasSelection && !sidebar {
            addImageMenu(to: menu, selection: selection, config: config)
        }

        if config.tool("openInTerminal") && !sidebar {
            menu.addItem(.separator())
            menu.addItem(item("在终端中打开", #selector(openInTerminal(_:))))
        }
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func addNewFileItems(to menu: NSMenu, config: AppConfig) {
        let enabled = config.fileTypes.enumerated().filter { $0.element.enabled && !$0.element.ext.isEmpty }
        guard !enabled.isEmpty else { return }

        let submenu = NSMenu(title: "新建")
        for (index, type) in enabled {
            // 父项已经叫「新建」，条目里不再重复「新建」二字
            let entry = item("\(type.displayName) (.\(type.ext))", #selector(newFile(_:)))
            entry.tag = index
            if config.showIconsInMenu, let icon = Self.icon(for: type.ext) {
                entry.image = icon
                // macOS 27：明确告诉 AppKit 这个图标要显示
                if #available(macOS 27.0, *) {
                    entry.preferredImageVisibility = .visible
                }
            }
            submenu.addItem(entry)
        }

        let parent = NSMenuItem(title: "新建", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        menu.addItem(parent)
    }

    /// 只有选中项里真的有图片时才出现，避免常年挂一堆用不上的项。
    private func addImageMenu(to menu: NSMenu, selection: [URL], config: AppConfig) {
        guard selection.contains(where: { ImageTools.isImage($0) }) else { return }

        let submenu = NSMenu(title: "图片")
        submenu.addItem(item("转为 PNG", #selector(convertPNG(_:))))
        submenu.addItem(item("转为 JPG", #selector(convertJPG(_:))))
        submenu.addItem(item("转为 HEIC", #selector(convertHEIC(_:))))
        submenu.addItem(item("转为 TIFF", #selector(convertTIFF(_:))))
        submenu.addItem(.separator())
        submenu.addItem(item("生成 macOS 图标集", #selector(makeMacIconSet(_:))))
        submenu.addItem(item("生成 iOS 图标集", #selector(makeIOSIconSet(_:))))
        submenu.addItem(item("生成 ICNS", #selector(makeICNS(_:))))
        submenu.addItem(.separator())
        submenu.addItem(item("设为墙纸", #selector(setAsWallpaper(_:))))

        let parent = NSMenuItem(title: "图片", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        menu.addItem(.separator())
        menu.addItem(parent)
    }

    private func addDestinationMenus(to menu: NSMenu, config: AppConfig) {
        let common = config.commonDirectories.enumerated().filter { $0.element.enabled }
        if !common.isEmpty {
            let submenu = NSMenu(title: "常用目录")
            for (index, entry) in common {
                let child = item(entry.displayName, #selector(openDirectory(_:)))
                child.tag = index
                submenu.addItem(child)
            }
            let parent = NSMenuItem(title: "常用目录", action: nil, keyEquivalent: "")
            parent.submenu = submenu
            menu.addItem(parent)
        }

        let destinations = config.sendToDirectories.enumerated().filter { $0.element.enabled }
        guard !destinations.isEmpty else { return }
        let title = config.sendMove ? "移动到" : "复制到"
        let submenu = NSMenu(title: title)
        for (index, entry) in destinations {
            let child = item(entry.displayName, #selector(sendTo(_:)))
            child.tag = index
            submenu.addItem(child)
        }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        menu.addItem(parent)
    }

    // MARK: - 剪切角标
    //
    // FinderSync 原生支持给文件打 badge。剪切之后文件没有任何视觉标记，
    // 用户不知道哪几个还在"待粘贴"状态里 —— 用角标补上。

    private static let cutBadgeIdentifier = "cut"
    private static var didRegisterCutBadge = false

    private func registerCutBadgeIfNeeded() {
        guard !Self.didRegisterCutBadge else { return }
        guard let image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "已剪切") else { return }
        FIFinderSyncController.default().setBadgeImage(image, label: "已剪切", forBadgeIdentifier: Self.cutBadgeIdentifier)
        Self.didRegisterCutBadge = true
    }

    private func setCutBadge(_ on: Bool, for urls: [URL]) {
        if on { registerCutBadgeIfNeeded() }
        for url in urls {
            FIFinderSyncController.default().setBadgeIdentifier(on ? Self.cutBadgeIdentifier : "", for: url)
        }
    }

    /// Finder 会问我们某个文件该显示什么角标（比如刚启动、或刷新时）。
    override func requestBadgeIdentifier(for url: URL) {
        guard currentConfig().pendingCut.contains(url.path) else { return }
        setCutBadge(true, for: [url])
    }

    // MARK: - 选择与目标目录

    private var selectedURLs: [URL] {
        FIFinderSyncController.default().selectedItemURLs() ?? []
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    /// 右键点在文件上 → 它所在目录；点在空白处 → 当前浏览的目录。
    private var targetDirectory: URL? {
        guard let first = selectedURLs.first else {
            return FIFinderSyncController.default().targetedURL()
        }
        return isDirectory(first) ? first : first.deletingLastPathComponent()
    }

    private func uniqueDestination(in directory: URL, name: String) -> URL {
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

    private func setPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// 每个动作第一条语句就调它，出问题时日志里能看到 Finder 到底传了什么。
    private func trace(_ name: String, _ sender: Any?) {
        let menuItem = sender as? NSMenuItem
        diag("action \(name) tag=\(menuItem?.tag ?? -1) 选中=\(selectedURLs.count)")
    }

    /// 复制路径之类的动作本身没有视觉反馈，靠提示音告诉用户点到了。
    private func feedback() {
        guard currentConfig().soundEnabled else { return }
        NSSound(named: NSSound.Name("Glass"))?.play()
    }

    private func fileType(for sender: NSMenuItem, config: AppConfig) -> FileType? {
        guard sender.tag >= 0, sender.tag < config.fileTypes.count else { return nil }
        return config.fileTypes[sender.tag]
    }

    private func directory(for sender: NSMenuItem, config: AppConfig, common: Bool) -> URL? {
        let list = common ? config.commonDirectories : config.sendToDirectories
        guard sender.tag >= 0, sender.tag < list.count else { return nil }
        return URL(fileURLWithPath: list[sender.tag].path)
    }

    // MARK: - 动作

    @objc func newFile(_ sender: NSMenuItem) {
        trace("newFile", sender)
        let config = currentConfig()
        guard let type = fileType(for: sender, config: config), let directory = targetDirectory else {
            diag("newFile 中断：解析不到类型或目录")
            return
        }
        let url = uniqueDestination(in: directory, name: "未命名.\(type.ext)")
        var contents = Data()
        if let template = type.template, !template.isEmpty,
           let data = try? Data(contentsOf: URL(fileURLWithPath: template)) {
            contents = data
        }
        let created = FileManager.default.createFile(atPath: url.path, contents: contents)
        diag("newFile .\(type.ext) created=\(created) → \(url.path)")
        guard created else { return }
        feedback()
        if config.openAfterCreate {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc func copyPath(_ sender: AnyObject?) {
        trace("copyPath", sender)
        setPasteboard(selectedURLs.map { $0.path }.joined(separator: "\n"))
        feedback()
    }

    @objc func copyName(_ sender: AnyObject?) {
        trace("copyName", sender)
        setPasteboard(selectedURLs.map { $0.lastPathComponent }.joined(separator: "\n"))
        feedback()
    }

    @objc func newFolderByName(_ sender: AnyObject?) {
        trace("newFolderByName", sender)
        for url in selectedURLs {
            let base = url.deletingPathExtension().lastPathComponent
            let target = uniqueDestination(in: url.deletingLastPathComponent(), name: base)
            try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        }
        feedback()
    }

    @objc func cut(_ sender: AnyObject?) {
        trace("cut", sender)
        let urls = selectedURLs
        var config = currentConfig()
        config.pendingCut = urls.map { $0.path }
        config.save()
        setCutBadge(true, for: urls)
        diag("剪切 \(urls.count) 项，已打角标")
        feedback()
    }

    @objc func pasteMove(_ sender: AnyObject?) {
        trace("pasteMove", sender)
        guard let directory = targetDirectory else { return }
        var config = currentConfig()
        let pending = config.pendingCut
        setCutBadge(false, for: pending.map { URL(fileURLWithPath: $0) })
        for path in pending where path != directory.path {
            let source = URL(fileURLWithPath: path)
            let destination = uniqueDestination(in: directory, name: source.lastPathComponent)
            do { try FileManager.default.moveItem(at: source, to: destination) }
            catch { diag("粘贴失败 \(source.path): \(error.localizedDescription)") }
        }
        config.pendingCut = []
        config.save()
        feedback()
    }

    @objc func sendTo(_ sender: NSMenuItem) {
        trace("sendTo", sender)
        let config = currentConfig()
        guard let directory = directory(for: sender, config: config, common: false) else { return }
        for source in selectedURLs {
            let destination = uniqueDestination(in: directory, name: source.lastPathComponent)
            do {
                if config.sendMove { try FileManager.default.moveItem(at: source, to: destination) }
                else { try FileManager.default.copyItem(at: source, to: destination) }
            } catch { diag("发送失败 \(source.path): \(error.localizedDescription)") }
        }
        feedback()
    }

    @objc func openDirectory(_ sender: NSMenuItem) {
        trace("openDirectory", sender)
        guard let directory = directory(for: sender, config: currentConfig(), common: true) else { return }
        NSWorkspace.shared.open(directory)
    }

    @objc func dissolveFolder(_ sender: AnyObject?) {
        trace("dissolveFolder", sender)
        for url in selectedURLs where isDirectory(url) {
            let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            let parent = url.deletingLastPathComponent()
            for child in children {
                let destination = uniqueDestination(in: parent, name: child.lastPathComponent)
                try? FileManager.default.moveItem(at: child, to: destination)
            }
            try? FileManager.default.removeItem(at: url)
        }
        feedback()
    }

    @objc func toggleHidden(_ sender: AnyObject?) {
        trace("toggleHidden", sender)
        for url in selectedURLs {
            var target = url
            var values = URLResourceValues()
            let hidden = (try? url.resourceValues(forKeys: [.isHiddenKey]))?.isHidden ?? false
            values.isHidden = !hidden
            try? target.setResourceValues(values)
        }
        feedback()
    }

    @objc func grantWrite(_ sender: AnyObject?) {
        trace("grantWrite", sender)
        for url in selectedURLs {
            let permissions = isDirectory(url) ? 0o755 : 0o644
            try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
        feedback()
    }

    @objc func shortcutOnDesktop(_ sender: AnyObject?) {
        trace("shortcutOnDesktop", sender)
        let desktop = AppPaths.realHome.appendingPathComponent("Desktop")
        for url in selectedURLs {
            let base = url.deletingPathExtension().lastPathComponent
            let link = uniqueDestination(in: desktop, name: "\(base) 快捷方式")
            try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        }
        feedback()
    }

    @objc func deletePermanently(_ sender: AnyObject?) {
        trace("deletePermanently", sender)
        for url in selectedURLs {
            do {
                try FileManager.default.removeItem(at: url)
                diag("彻底删除成功 \(url.path)")
            } catch {
                diag("彻底删除失败 \(url.path): \(error.localizedDescription)")
            }
        }
        feedback()
    }

    @objc func fileInfo(_ sender: AnyObject?) {
        trace("fileInfo", sender)
        var lines: [String] = []
        for url in selectedURLs {
            let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            lines.append("名称：\(url.lastPathComponent)")
            lines.append("路径：\(url.path)")
            lines.append("大小：\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
            if let created = attributes[.creationDate] as? Date {
                lines.append("创建：\(Self.dateFormatter.string(from: created))")
            }
            if let modified = attributes[.modificationDate] as? Date {
                lines.append("修改：\(Self.dateFormatter.string(from: modified))")
            }
            if !isDirectory(url) {
                let (md5, sha256) = hashes(url)
                lines.append("MD5：\(md5)")
                lines.append("SHA256：\(sha256)")
            }
            lines.append("")
        }
        let text = lines.joined(separator: "\n")
        setPasteboard(text)
        try? text.write(to: AppPaths.lastInfoFile, atomically: true, encoding: .utf8)
        feedback()
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("SuperRightClickShowInfo"), object: nil, userInfo: nil, deliverImmediately: true)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--show-info"]
        NSWorkspace.shared.openApplication(at: AppPaths.hostApp, configuration: configuration) { _, error in
            if let error { diag("拉起主 App 失败：\(error.localizedDescription)") }
        }
    }

    @objc func openInTerminal(_ sender: AnyObject?) {
        trace("openInTerminal", sender)
        guard let directory = targetDirectory else { return }
        let app = URL(fileURLWithPath: currentConfig().terminalApp)
        NSWorkspace.shared.open([directory], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - 图片动作

    private var selectedImages: [URL] {
        selectedURLs.filter { ImageTools.isImage($0) }
    }

    private func convertImages(to type: UTType, label: String) {
        let images = selectedImages
        var done = 0
        for url in images where ImageTools.convert(url, to: type) != nil { done += 1 }
        diag("转为 \(label)：\(done)/\(images.count)")
        if done > 0 { feedback() }
    }

    private func makeIconSets(iOS: Bool) {
        let images = selectedImages
        var done = 0
        for url in images where ImageTools.makeIconSet(url, iOS: iOS) != nil { done += 1 }
        diag("生成 \(iOS ? "iOS" : "macOS") 图标集：\(done)/\(images.count)")
        if done > 0 { feedback() }
    }

    @objc func convertPNG(_ sender: AnyObject?) { trace("convertPNG", sender); convertImages(to: .png, label: "PNG") }
    @objc func convertJPG(_ sender: AnyObject?) { trace("convertJPG", sender); convertImages(to: .jpeg, label: "JPG") }
    @objc func convertHEIC(_ sender: AnyObject?) { trace("convertHEIC", sender); convertImages(to: .heic, label: "HEIC") }
    @objc func convertTIFF(_ sender: AnyObject?) { trace("convertTIFF", sender); convertImages(to: .tiff, label: "TIFF") }
    @objc func makeMacIconSet(_ sender: AnyObject?) { trace("makeMacIconSet", sender); makeIconSets(iOS: false) }
    @objc func makeIOSIconSet(_ sender: AnyObject?) { trace("makeIOSIconSet", sender); makeIconSets(iOS: true) }

    @objc func makeICNS(_ sender: AnyObject?) {
        trace("makeICNS", sender)
        let images = selectedImages
        var done = 0
        for url in images where ImageTools.makeICNS(url) != nil { done += 1 }
        diag("生成 ICNS：\(done)/\(images.count)")
        if done > 0 { feedback() }
    }

    @objc func setAsWallpaper(_ sender: AnyObject?) {
        trace("setAsWallpaper", sender)
        guard let first = selectedImages.first, ImageTools.setAsWallpaper(first) else { return }
        feedback()
    }

    // MARK: - 哈希

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private func hashes(_ url: URL) -> (String, String) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return ("读取失败", "读取失败") }
        defer { try? handle.close() }
        var md5 = Insecure.MD5()
        var sha256 = SHA256()
        while let data = try? handle.read(upToCount: 1 << 16), !data.isEmpty {
            md5.update(data: data)
            sha256.update(data: data)
        }
        let md5Text = md5.finalize().map { String(format: "%02x", $0) }.joined()
        let shaText = sha256.finalize().map { String(format: "%02x", $0) }.joined()
        return (md5Text, shaText)
    }
}
