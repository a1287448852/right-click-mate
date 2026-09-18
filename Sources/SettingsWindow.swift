import Cocoa

/// 滚动视图的 documentView 需要翻转坐标，否则内容会贴底。
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 卡片：安静容器，靠边框和留白定义，不做装饰（设计系统 card.json）。
/// 用 updateLayer 让配色跟随浅色/深色切换。
final class CardView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = Theme.radiusCard
        layer.borderWidth = 1
        layer.borderColor = Theme.Palette.border.cgColor
        layer.backgroundColor = Theme.Palette.card.cgColor
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.05
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 0, height: -1)
    }
}

/// 画布：极淡的品牌色渐变。玻璃需要有东西可折射，纯平底色上玻璃看不出来。
final class CanvasView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.backgroundColor = Theme.Palette.canvas.cgColor
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 整幅斜向淡染。玻璃需要有明暗可折射，纯平底色上玻璃等于不存在。
        let wash = bounds
        NSGradient(colors: [
            Theme.Palette.brand.withAlphaComponent(0.16),
            Theme.Palette.brand.withAlphaComponent(0.02),
        ])?.draw(in: wash, angle: -65)
    }
}

/// 侧栏条目
final class SidebarButton: NSButton {
    let paneIndex: Int
    private let paneTitle: String
    var isSelected = false { didSet { refresh() } }

    init(title: String, symbol: String, index: Int, target: AnyObject, action: Selector) {
        self.paneTitle = title
        self.paneIndex = index
        super.init(frame: .zero)
        self.target = target
        self.action = action
        self.tag = index
        isBordered = false
        alignment = .left
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        imagePosition = .imageLeading
        imageScaling = .scaleProportionallyDown
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 32).isActive = true
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = Theme.radiusControl
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        let tint: NSColor = isSelected ? Theme.Palette.accent : .labelColor
        attributedTitle = NSAttributedString(string: "  " + paneTitle, attributes: [
            .font: Theme.font(13, isSelected ? .semibold : .medium),
            .foregroundColor: tint,
        ])
        contentTintColor = isSelected ? Theme.Palette.accent : .secondaryLabelColor
        needsDisplay = true
    }
}

/// 侧栏：整块 Liquid Glass 面板，选中态是一枚可交互的玻璃胶囊。
final class SidebarView: NSView {
    private let glass = NSGlassEffectView()
    private let selection = NSGlassEffectView()
    private let stack = NSStackView()
    private(set) var buttons: [SidebarButton] = []
    var onSelect: ((Int) -> Void)?
    private(set) var selectedIndex = 0

    private let inset: CGFloat = 12
    private let pillHeight: CGFloat = 32
    private let pillSpacing: CGFloat = 4
    private let pillTop: CGFloat = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        glass.style = .regular
        glass.cornerRadius = Theme.radiusGlass
        glass.tintColor = Theme.Palette.brand.withAlphaComponent(0.05)
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        selection.style = .clear
        // 设计系统的 sidebar-accent 是"浅底 + 深字"（#e5e5ea / #1d1d1f），不是"实色底 + 白字"。
        // 白色文字压在浅色玻璃上对比度不够，改成淡蓝玻璃 + 品牌蓝文字。
        selection.tintColor = Theme.Palette.accent.withAlphaComponent(0.20)
        selection.cornerRadius = Theme.radiusControl
        if #available(macOS 27.0, *) {
            selection.effectIsInteractive = true
        }

        stack.orientation = .vertical
        stack.spacing = pillSpacing
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = stack
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// 侧栏顶部：App 图标 + 名称，给整块玻璃一个视觉锚点。
    func addHeader(icon: NSImage, title: String, subtitle: String) {
        let imageView = NSImageView(image: icon)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 46),
            imageView.heightAnchor.constraint(equalToConstant: 46),
        ])

        let name = NSTextField(labelWithString: title)
        name.font = Theme.font(13, .semibold)
        let version = NSTextField(labelWithString: subtitle)
        version.font = Theme.font(11)
        version.textColor = .secondaryLabelColor

        let text = NSStackView(views: [name, version])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        let header = NSStackView(views: [imageView, text])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10
        header.edgeInsets = NSEdgeInsets(top: 22, left: 2, bottom: 14, right: 2)
        stack.insertArrangedSubview(header, at: 0)
        stack.setCustomSpacing(10, after: header)
    }

    func addItem(title: String, symbol: String) {
        let button = SidebarButton(title: title, symbol: symbol, index: buttons.count,
                                   target: self, action: #selector(clicked(_:)))
        buttons.append(button)
        stack.addArrangedSubview(button)
        button.widthAnchor.constraint(equalToConstant: Theme.sidebarWidth - inset * 2 - 12).isActive = true
        if buttons.count == 1 {
            // 放在 stack 之下：选中高亮必须在内容后面，否则会把图标和文字盖住
            glass.addSubview(selection, positioned: .below, relativeTo: stack)
        }
    }

    @objc private func clicked(_ sender: SidebarButton) {
        select(sender.paneIndex, animated: true)
        onSelect?(sender.paneIndex)
    }

    func select(_ index: Int, animated: Bool) {
        selectedIndex = index
        for button in buttons { button.isSelected = button.paneIndex == index }
        needsLayout = true
        layoutSubtreeIfNeeded()
        positionSelection(animated: animated)
    }

    override func layout() {
        super.layout()
        positionSelection(animated: false)
    }

    private func positionSelection(animated: Bool) {
        guard selectedIndex < buttons.count else { return }
        let button = buttons[selectedIndex]
        let frame = button.convert(button.bounds, to: glass)
        let target = NSRect(x: frame.minX - 6, y: frame.minY, width: frame.width + 12, height: frame.height)
        guard target != selection.frame else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
                selection.animator().frame = target
            }
        } else {
            selection.frame = target
        }
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {

    private var config: AppConfig
    private var sidebar: SidebarView!
    private var paneScroll = NSScrollView()
    private var paneContainer = FlippedView()
    private var currentPane = 0

    private let paneItems: [(title: String, symbol: String)] = [
        ("通用设置", "gearshape"),
        ("新建文件", "doc.badge.plus"),
        ("发送文件到", "tray.and.arrow.up"),
        ("常用目录", "folder"),
        ("工具箱", "wrench.and.screwdriver"),
    ]

    init(config: AppConfig) {
        self.config = config
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = AppInfo.name
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        super.init(window: window)
        window.delegate = self
        buildLayout()
        sidebar.select(0, animated: false)
        show(pane: 0)
        ensureOnScreen()
    }

    /// 兜底：窗口若完全落在所有屏幕之外（拔掉外接屏、或系统摆到不存在的坐标上），
    /// 搬回主屏。只跟主屏判交会把它从副屏硬拽回来，所以要跟所有屏幕的并集比。
    private func ensureOnScreen() {
        guard let window else { return }
        let onAnyScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
        guard !onAnyScreen, let main = NSScreen.main?.visibleFrame else { return }
        var frame = window.frame
        frame.origin = NSPoint(x: main.midX - frame.width / 2, y: main.midY - frame.height / 2)
        window.setFrame(frame, display: true)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - 布局

    private func buildLayout() {
        guard let window else { return }
        let root = CanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        root.wantsLayer = true

        sidebar = SidebarView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addHeader(icon: NSApplication.shared.applicationIconImage ?? NSImage(),
                          title: AppInfo.name,
                          subtitle: "版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1")")
        for item in paneItems {
            sidebar.addItem(title: item.title, symbol: item.symbol)
        }
        sidebar.onSelect = { [weak self] index in self?.show(pane: index) }

        paneScroll.hasVerticalScroller = true
        paneScroll.drawsBackground = false
        paneScroll.documentView = paneContainer
        paneScroll.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(sidebar)
        root.addSubview(paneScroll)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            sidebar.widthAnchor.constraint(equalToConstant: Theme.sidebarWidth),
            paneScroll.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 8),
            paneScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            paneScroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            paneScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        window.contentView = root
    }

    private func show(pane: Int) {
        currentPane = pane
        rebuildPane()
    }

    private func rebuildPane() {
        paneContainer.subviews.forEach { $0.removeFromSuperview() }
        let content = buildPane(index: currentPane)
        let width = max(paneScroll.contentSize.width, 480)
        content.translatesAutoresizingMaskIntoConstraints = true
        content.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        content.layoutSubtreeIfNeeded()
        let height = content.fittingSize.height + 48
        content.frame = NSRect(x: 0, y: 0, width: width, height: height)
        paneContainer.addSubview(content)
        paneContainer.frame = NSRect(x: 0, y: 0, width: width, height: height)
        paneScroll.contentView.scroll(to: .zero)
        paneScroll.reflectScrolledClipView(paneScroll.contentView)
    }

    func windowDidResize(_ notification: Notification) {
        rebuildPane()
    }

    // MARK: - 控件工厂

    private func paneStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Theme.space12
        stack.edgeInsets = NSEdgeInsets(top: Theme.space24, left: Theme.space24,
                                        bottom: Theme.space32, right: Theme.space24)
        return stack
    }

    private func pageHeader(_ title: String, _ subtitle: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        let heading = NSTextField(labelWithString: title)
        heading.font = Theme.font(20, .semibold)
        let sub = NSTextField(labelWithString: subtitle)
        sub.font = Theme.font(12)
        sub.textColor = .secondaryLabelColor
        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(sub)
        return stack
    }

    private func card(_ rows: [NSView]) -> CardView {
        let box = CardView()
        box.wantsLayer = true
        let inner = NSStackView(views: rows)
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = Theme.space8
        inner.edgeInsets = NSEdgeInsets(top: Theme.space12, left: Theme.space16,
                                        bottom: Theme.space12, right: Theme.space16)
        inner.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            inner.topAnchor.constraint(equalTo: box.topAnchor),
            inner.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        return box
    }

    private func caption(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = Theme.font(11)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = Theme.contentWidth - 32
        return label
    }

    private func toggleRow(_ title: String, value: Bool, action: Selector, id: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = Theme.font(13)
        let toggle = NSSwitch()
        toggle.state = value ? .on : .off
        toggle.target = self
        toggle.action = action
        toggle.identifier = NSUserInterfaceItemIdentifier(id)
        toggle.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [label, NSView(), toggle])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Theme.space8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: Theme.contentWidth - 32).isActive = true
        return row
    }

    private func textRow(_ title: String, value: String, action: Selector, id: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = Theme.font(13)
        let field = NSTextField(string: value)
        field.isEditable = true
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.font = Theme.mono(12)
        field.target = self
        field.action = action
        field.delegate = self
        field.identifier = NSUserInterfaceItemIdentifier(id)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let row = NSStackView(views: [label, NSView(), field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Theme.space8
        return row
    }

    private func columnHeader(_ labels: [(String, CGFloat)]) -> NSView {
        let views: [NSView] = labels.map { title, width in
            let label = NSTextField(labelWithString: title)
            label.font = Theme.font(11, .medium)
            label.textColor = .secondaryLabelColor
            if width > 0 {
                label.translatesAutoresizingMaskIntoConstraints = false
                label.widthAnchor.constraint(equalToConstant: width).isActive = true
            }
            return label
        }
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Theme.space8
        return stack
    }

    private func toggle(value: Bool, action: Selector, id: String, width: CGFloat = 0) -> NSSwitch {
        let toggle = NSSwitch()
        toggle.state = value ? .on : .off
        toggle.target = self
        toggle.action = action
        toggle.identifier = NSUserInterfaceItemIdentifier(id)
        if width > 0 {
            toggle.translatesAutoresizingMaskIntoConstraints = false
            toggle.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return toggle
    }

    private func textField(_ value: String, action: Selector, id: String, width: CGFloat) -> NSTextField {
        let field = NSTextField(string: value)
        field.isEditable = true
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.font = Theme.font(12)
        field.target = self
        field.action = action
        field.delegate = self
        field.identifier = NSUserInterfaceItemIdentifier(id)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        return field
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Theme.space8
        return stack
    }

    private func plainButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    // MARK: - 各面板

    private func buildPane(index: Int) -> NSStackView {
        switch index {
        case 0: return buildGeneralPane()
        case 1: return buildFileTypePane()
        case 2: return buildSendToPane()
        case 3: return buildCommonDirectoryPane()
        default: return buildToolPane()
        }
    }

    private func buildGeneralPane() -> NSStackView {
        let stack = paneStack()
        stack.addArrangedSubview(pageHeader("通用设置", "启动行为、外观与文件路径"))
        stack.addArrangedSubview(card([
            toggleRow("显示菜单栏图标", value: config.showMenuBarIcon,
                      action: #selector(generalChanged(_:)), id: "general.showMenuBarIcon"),
            toggleRow("右键菜单里显示图标", value: config.showIconsInMenu,
                      action: #selector(generalChanged(_:)), id: "general.showIconsInMenu"),
            toggleRow("操作后播放提示音", value: config.soundEnabled,
                      action: #selector(generalChanged(_:)), id: "general.soundEnabled"),
            toggleRow("新建文件后自动打开", value: config.openAfterCreate,
                      action: #selector(generalChanged(_:)), id: "general.openAfterCreate"),
            caption("复制路径、剪切这类操作本身没有视觉反馈，靠提示音确认。"),
        ]))
        stack.addArrangedSubview(card([
            textRow("终端 App", value: config.terminalApp,
                    action: #selector(generalChanged(_:)), id: "general.terminalApp"),
            caption("「在终端中打开」会用这个 App。默认是系统自带的终端。"),
        ]))
        stack.addArrangedSubview(card([
            toggleRow("发送时用「移动」而不是「复制」", value: config.sendMove,
                      action: #selector(generalChanged(_:)), id: "general.sendMove"),
            caption("「剪切」会记住选中的文件，到目标目录右键选「粘贴到此处」完成移动。"),
        ]))
        stack.addArrangedSubview(card([
            caption("配置文件：\(AppPaths.configFile.path)"),
            caption("诊断日志：\(AppPaths.diagFile.path)"),
        ]))
        return stack
    }

    private func buildFileTypePane() -> NSStackView {
        let stack = paneStack()
        stack.addArrangedSubview(pageHeader("新建文件", "右键菜单里可以创建的文件类型"))
        stack.addArrangedSubview(columnHeader([("启用", 50), ("显示名称", 150), ("后缀", 70), ("置顶", 50), ("", 0)]))

        var rows: [NSView] = []
        for (index, type) in config.fileTypes.enumerated() {
            let remove = plainButton("删除", action: #selector(removeFileType(_:)))
            remove.identifier = NSUserInterfaceItemIdentifier("fileType.\(index)")
            remove.controlSize = .small
            remove.font = Theme.font(11)
            rows.append(row([
                toggle(value: type.enabled, action: #selector(fileTypeChanged(_:)),
                       id: "fileType.\(index).enabled", width: 50),
                textField(type.displayName, action: #selector(fileTypeChanged(_:)),
                          id: "fileType.\(index).displayName", width: 150),
                textField(type.ext, action: #selector(fileTypeChanged(_:)), id: "fileType.\(index).ext", width: 70),
                toggle(value: type.inMainMenu, action: #selector(fileTypeChanged(_:)),
                       id: "fileType.\(index).inMainMenu", width: 50),
                remove,
            ]))
        }
        rows.append(plainButton("添加类型", action: #selector(addFileType(_:))))
        stack.addArrangedSubview(card(rows))
        stack.addArrangedSubview(caption("勾「置顶」的类型直接放在「\(AppInfo.name)」子菜单第一层，否则再收进「新建文件」二级子菜单。"))
        return stack
    }

    private func buildSendToPane() -> NSStackView {
        let stack = paneStack()
        stack.addArrangedSubview(pageHeader("发送文件到", "右键把文件复制或移动到哪里"))
        stack.addArrangedSubview(columnHeader([("启用", 50), ("显示名称", 130), ("真实路径", 280), ("", 0)]))

        var rows: [NSView] = []
        for (index, entry) in config.sendToDirectories.enumerated() {
            let remove = plainButton("删除", action: #selector(removeSendTo(_:)))
            remove.identifier = NSUserInterfaceItemIdentifier("sendTo.\(index)")
            remove.controlSize = .small
            remove.font = Theme.font(11)
            rows.append(row([
                toggle(value: entry.enabled, action: #selector(sendToChanged(_:)),
                       id: "sendTo.\(index).enabled", width: 50),
                textField(entry.displayName, action: #selector(sendToChanged(_:)),
                          id: "sendTo.\(index).displayName", width: 130),
                textField(entry.path, action: #selector(sendToChanged(_:)), id: "sendTo.\(index).path", width: 280),
                remove,
            ]))
        }
        rows.append(plainButton("添加目录", action: #selector(addSendTo(_:))))
        stack.addArrangedSubview(card(rows))
        return stack
    }

    private func buildCommonDirectoryPane() -> NSStackView {
        let stack = paneStack()
        stack.addArrangedSubview(pageHeader("常用目录", "一键在访达里跳转的目录"))
        stack.addArrangedSubview(columnHeader([("启用", 50), ("显示名称", 130), ("真实路径", 280), ("", 0)]))

        var rows: [NSView] = []
        for (index, entry) in config.commonDirectories.enumerated() {
            let remove = plainButton("删除", action: #selector(removeCommonDirectory(_:)))
            remove.identifier = NSUserInterfaceItemIdentifier("commonDir.\(index)")
            remove.controlSize = .small
            remove.font = Theme.font(11)
            rows.append(row([
                toggle(value: entry.enabled, action: #selector(commonDirectoryChanged(_:)),
                       id: "commonDir.\(index).enabled", width: 50),
                textField(entry.displayName, action: #selector(commonDirectoryChanged(_:)),
                          id: "commonDir.\(index).displayName", width: 130),
                textField(entry.path, action: #selector(commonDirectoryChanged(_:)),
                          id: "commonDir.\(index).path", width: 280),
                remove,
            ]))
        }
        rows.append(plainButton("添加目录", action: #selector(addCommonDirectory(_:))))
        stack.addArrangedSubview(card(rows))
        return stack
    }

    private func buildToolPane() -> NSStackView {
        let stack = paneStack()
        stack.addArrangedSubview(pageHeader("工具箱", "右键菜单里出现的单项功能"))

        var rows: [NSView] = []
        for tool in ToolKey.all {
            rows.append(toggleRow(tool.title, value: config.tool(tool.key),
                                  action: #selector(toolChanged(_:)), id: "tool.\(tool.key)"))
        }
        stack.addArrangedSubview(card(rows))
        stack.addArrangedSubview(card([
            caption("注意：「彻底删除」不进废纸篓，点了就没了。"),
        ]))
        return stack
    }

    // MARK: - 变更处理

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              let id = field.identifier?.rawValue else { return }
        if id.hasPrefix("general.") { generalChanged(field) }
        else if id.hasPrefix("fileType.") { fileTypeChanged(field) }
        else if id.hasPrefix("sendTo.") { sendToChanged(field) }
        else if id.hasPrefix("commonDir.") { commonDirectoryChanged(field) }
    }

    @objc private func generalChanged(_ sender: NSControl) {
        guard let key = sender.identifier?.rawValue else { return }
        let on = (sender as? NSSwitch)?.state == .on
        let text = (sender as? NSTextField)?.stringValue ?? ""
        switch key {
        case "general.showMenuBarIcon": config.showMenuBarIcon = on
        case "general.showIconsInMenu": config.showIconsInMenu = on
        case "general.soundEnabled": config.soundEnabled = on
        case "general.openAfterCreate": config.openAfterCreate = on
        case "general.sendMove": config.sendMove = on
        case "general.terminalApp": config.terminalApp = text
        default: break
        }
        config.save()
    }

    @objc private func fileTypeChanged(_ sender: NSControl) {
        guard let parts = split(sender), parts.count == 3, let index = Int(parts[1]),
              index < config.fileTypes.count else { return }
        switch parts[2] {
        case "enabled": config.fileTypes[index].enabled = (sender as? NSSwitch)?.state == .on
        case "inMainMenu": config.fileTypes[index].inMainMenu = (sender as? NSSwitch)?.state == .on
        case "displayName": config.fileTypes[index].displayName = (sender as? NSTextField)?.stringValue ?? ""
        case "ext": config.fileTypes[index].ext = (sender as? NSTextField)?.stringValue ?? ""
        default: break
        }
        config.save()
    }

    @objc private func sendToChanged(_ sender: NSControl) {
        guard let parts = split(sender), parts.count == 3, let index = Int(parts[1]),
              index < config.sendToDirectories.count else { return }
        switch parts[2] {
        case "enabled": config.sendToDirectories[index].enabled = (sender as? NSSwitch)?.state == .on
        case "displayName": config.sendToDirectories[index].displayName = (sender as? NSTextField)?.stringValue ?? ""
        case "path": config.sendToDirectories[index].path = (sender as? NSTextField)?.stringValue ?? ""
        default: break
        }
        config.save()
    }

    @objc private func commonDirectoryChanged(_ sender: NSControl) {
        guard let parts = split(sender), parts.count == 3, let index = Int(parts[1]),
              index < config.commonDirectories.count else { return }
        switch parts[2] {
        case "enabled": config.commonDirectories[index].enabled = (sender as? NSSwitch)?.state == .on
        case "displayName": config.commonDirectories[index].displayName = (sender as? NSTextField)?.stringValue ?? ""
        case "path": config.commonDirectories[index].path = (sender as? NSTextField)?.stringValue ?? ""
        default: break
        }
        config.save()
    }

    @objc private func toolChanged(_ sender: NSSwitch) {
        guard let key = sender.identifier?.rawValue else { return }
        config.tools[String(key.dropFirst("tool.".count))] = (sender.state == .on)
        config.save()
    }

    @objc private func addFileType(_ sender: Any?) {
        config.fileTypes.append(FileType(displayName: "新类型", ext: "txt", enabled: true,
                                        inMainMenu: false, template: nil))
        config.save()
        rebuildPane()
    }

    @objc private func removeFileType(_ sender: NSButton) {
        guard let index = index(from: sender, prefix: "fileType.") else { return }
        config.fileTypes.remove(at: index)
        config.save()
        rebuildPane()
    }

    @objc private func addSendTo(_ sender: Any?) {
        config.sendToDirectories.append(Shortcut(displayName: "新目录",
                                                 path: AppPaths.realHome.appendingPathComponent("Desktop").path,
                                                 enabled: true))
        config.save()
        rebuildPane()
    }

    @objc private func removeSendTo(_ sender: NSButton) {
        guard let index = index(from: sender, prefix: "sendTo.") else { return }
        config.sendToDirectories.remove(at: index)
        config.save()
        rebuildPane()
    }

    @objc private func addCommonDirectory(_ sender: Any?) {
        config.commonDirectories.append(Shortcut(displayName: "新目录",
                                                 path: AppPaths.realHome.appendingPathComponent("Desktop").path,
                                                 enabled: true))
        config.save()
        rebuildPane()
    }

    @objc private func removeCommonDirectory(_ sender: NSButton) {
        guard let index = index(from: sender, prefix: "commonDir.") else { return }
        config.commonDirectories.remove(at: index)
        config.save()
        rebuildPane()
    }

    private func split(_ sender: NSControl) -> [String]? {
        sender.identifier?.rawValue.split(separator: ".").map(String.init)
    }

    private func index(from sender: NSButton, prefix: String) -> Int? {
        guard let raw = sender.identifier?.rawValue, raw.hasPrefix(prefix) else { return nil }
        return Int(raw.dropFirst(prefix.count))
    }
}
