import SwiftUI
import FinderSync
import UniformTypeIdentifiers

// SwiftUI 版设置界面。
//
// 严格遵守 Apple《Adopting Liquid Glass》的规定：
//   1. 玻璃属于"导航层 / 控件层"，绝不铺在内容层上
//   2. 玻璃不能叠玻璃 —— 系统组件自己已经是玻璃，不要再套一层自绘玻璃
//   3. 自绘玻璃只保留在最关键的功能元素上
//
// 所以：侧栏用 NavigationSplitView 的系统 List（自动 Liquid Glass）、
// 内容用 Form(.grouped) 和 List（无玻璃）、
// 自绘玻璃只有底部那枚会形变的状态胶囊。
//
// 用了 macOS 27 的新特性：DynamicViewContent.reorderable() 拖拽排序。

// MARK: - 菜单栏驻留

/// 菜单栏状态项。
///
/// 用 AppKit 的 `NSStatusItem` 而不是 SwiftUI 的 `MenuBarExtra` ——
/// 同样都是苹果官方 API（`MenuBarExtra` 底层就是它），但这里行为完全确定，
/// 不会出现"加了 Scene 却什么都没显示"这种看不见摸不着的状况。
final class StatusItemController: NSObject {
    static let shared = StatusItemController()
    private var statusItem: NSStatusItem?

    private override init() { super.init() }

    func setVisible(_ visible: Bool) {
        visible ? install() : uninstall()
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "cursorarrow.click", accessibilityDescription: AppInfo.name)
            image?.isTemplate = true
            button.image = image
            button.toolTip = AppInfo.name
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "打开设置…", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(withTitle: "访达扩展管理…", action: #selector(openExtensionSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 \(AppInfo.name)", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu

        statusItem = item
        diag("菜单栏状态项已安装")
    }

    private func uninstall() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
        diag("菜单栏状态项已移除")
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func openExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// 菜单栏图标可见性。
///
/// 开关打开时 App 走 `.accessory` 激活策略 —— **不占 Dock、不进 ⌘Tab**，只驻留菜单栏。
/// 关掉时回到 `.regular`，否则用户会同时失去 Dock 图标和菜单栏图标，等于没有任何入口。
final class MenuBarVisibility: ObservableObject {
    static let shared = MenuBarVisibility()

    @Published var isInserted: Bool = AppConfig.load().showMenuBarIcon {
        didSet { applyPolicy() }
    }

    private init() {}

    func applyPolicy() {
        NSApp.setActivationPolicy(isInserted ? .accessory : .regular)
        StatusItemController.shared.setVisible(isInserted)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 属性观察器在 init 期间不触发，所以启动时要显式应用一次。
        // 延后一个主队列轮次，避免和 SwiftUI 建窗口的过程抢时序。
        DispatchQueue.main.async {
            MenuBarVisibility.shared.applyPolicy()
        }
    }

    /// 驻留菜单栏时，关掉设置窗口不退出 App
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !MenuBarVisibility.shared.isInserted
    }
}

@main
struct RightClickMateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window(AppInfo.name, id: "settings") {
            SettingsView()
                .background(TransparentWindow())
        }
        .defaultSize(width: 940, height: 660)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// 把窗口设为透明。
///
/// 这是"用了 Liquid Glass 却看不出玻璃"的根因：不透明窗口上，系统侧栏和工具栏
/// 的玻璃没有背后的内容可以采样，渲染出来就是一块灰板。
/// 系统设置、备忘录这些 App 的窗口都是半透明的，玻璃才显形。
private struct TransparentWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        DispatchQueue.main.async {
            guard let window = probe.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// 注意：这里**故意不再铺一层 NSVisualEffectView 背板**。
//
// 之前铺了一层 .underWindowBackground，结果是两层模糊叠加（窗口背板 + 系统侧栏材质），
// 糊成一块灰板，反而更不玻璃。窗口一旦透明，系统侧栏材质自己就会采样桌面 ——
// 单层采样才通透。

enum Pane: String, CaseIterable, Identifiable, Hashable {
    case general, newFile, sendTo, commonDirectories, tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用设置"
        case .newFile: return "新建文件"
        case .sendTo: return "发送文件到"
        case .commonDirectories: return "常用目录"
        case .tools: return "工具箱"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .newFile: return "doc.badge.plus"
        case .sendTo: return "tray.and.arrow.up"
        case .commonDirectories: return "folder"
        case .tools: return "wrench.and.screwdriver"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "启动行为、外观与文件路径"
        case .newFile: return "右键菜单里可以创建的文件类型，拖动可调顺序"
        case .sendTo: return "右键把文件复制或移动到哪里，拖动可调顺序"
        case .commonDirectories: return "一键在访达里跳转的目录，拖动可调顺序"
        case .tools: return "右键菜单里出现的单项功能"
        }
    }

    /// 列表顺序就是右键菜单顺序，这几个面板支持拖拽排序。
    var supportsReordering: Bool {
        switch self {
        case .newFile, .sendTo, .commonDirectories: return true
        case .general, .tools: return false
        }
    }
}

struct SettingsView: View {
    @State private var config = AppConfig.load()
    @State private var pane: Pane = .general

    @Namespace private var glassNamespace
    @State private var justSaved = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 240)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pane.title).font(.title2.weight(.semibold))
                    Text(pane.subtitle).font(.callout).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 14)

                switch pane {
                case .general:
                    ScrollView { GeneralPane(config: $config).padding(.horizontal, 20) }
                case .tools:
                    ScrollView { ToolsPane(config: $config).padding(.horizontal, 20) }
                case .newFile:
                    FileTypesPane(config: $config)
                case .sendTo:
                    DirectoryPane(config: $config, kind: .sendTo)
                case .commonDirectories:
                    DirectoryPane(config: $config, kind: .common)
                }
            }
            // 内容层保持不透明：玻璃只在导航层，内容要保证文字对比度
            .background(Color(nsColor: .windowBackgroundColor))
            .safeAreaInset(edge: .bottom) { statusBar }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    FIFinderSyncController.showExtensionManagementInterface()
                } label: {
                    Label("扩展管理", systemImage: "puzzlepiece.extension")
                }
                .help("打开系统设置里的访达扩展面板")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    config = .standard
                } label: {
                    Label("恢复默认", systemImage: "arrow.counterclockwise")
                }
                .help("把所有设置恢复成出厂默认值")
            }
        }
        // 防抖保存：之前每敲一个字符就写一次盘，敲错一个键就把错误值永久写进配置。
        .onChange(of: config) { _, newValue in
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                newValue.save()
                flash()
            }
        }
    }

    /// 全 app 唯一的自绘玻璃：底部状态胶囊。
    /// GlassEffectContainer 共享采样区域，glassEffectID + matchedGeometry 让它在两个状态间形变。
    private var statusBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: justSaved ? "checkmark.circle.fill" : "circle.dotted")
                Text(justSaved ? "已保存" : "改动即时生效")
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .glassEffect(.regular.tint(justSaved ? .green : nil).interactive(), in: .capsule)
            .glassEffectID("status", in: glassNamespace)
            .glassEffectTransition(.matchedGeometry)
        }
        .padding(.bottom, 16)
    }

    private func flash() {
        withAnimation(.bouncy) { justSaved = true }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.bouncy) { justSaved = false }
        }
    }
}

// MARK: - 拖拽排序

/// 把 macOS 27 的 ReorderDifference 落到数组上。
func applyReorder<Item: Identifiable>(
    _ difference: ReorderDifference<Item.ID, ReorderableSingleCollectionIdentifier>,
    to items: inout [Item]
) {
    let moving = items.filter { difference.sources.contains($0.id) }
    guard !moving.isEmpty else { return }
    items.removeAll { difference.sources.contains($0.id) }
    switch difference.destination.position {
    case .before(let id):
        let index = items.firstIndex { $0.id == id } ?? items.endIndex
        items.insert(contentsOf: moving, at: index)
    case .end:
        items.append(contentsOf: moving)
    }
}

// MARK: - 通用设置

struct GeneralPane: View {
    @Binding var config: AppConfig
    @State private var choosingTerminal = false

    var body: some View {
        Form {
            Section {
                Toggle("显示菜单栏图标", isOn: $config.showMenuBarIcon)
                Toggle("右键菜单里显示图标", isOn: $config.showIconsInMenu)
                Toggle("操作后播放提示音", isOn: $config.soundEnabled)
                Toggle("新建文件后自动打开", isOn: $config.openAfterCreate)
            } header: {
                Text("启动与显示")
            } footer: {
                Text("开启菜单栏图标后，\(AppInfo.name) 只驻留菜单栏 —— 不占 Dock、不进 ⌘Tab；关掉设置窗口也不会退出。关掉这个开关则回到 Dock。")
            }
            Section {
                LabeledContent("终端 App") {
                    HStack(spacing: 8) {
                        Text(config.terminalApp)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 280, alignment: .trailing)
                        Button("选择…") { choosingTerminal = true }
                    }
                }
            } header: {
                Text("在终端中打开")
            } footer: {
                Text("用系统选择器挑 App，避免手打路径写错。默认是系统自带的终端。")
            }
            Section {
                Toggle("发送时用「移动」而不是「复制」", isOn: $config.sendMove)
            } header: {
                Text("发送文件")
            } footer: {
                Text("「剪切」会记住选中的文件，到目标目录右键选「粘贴到此处」完成移动。")
            }
            Section {
                Button {
                    FIFinderSyncController.showExtensionManagementInterface()
                } label: {
                    Label("打开访达扩展管理面板", systemImage: "puzzlepiece.extension")
                }
            } header: {
                Text("访达扩展")
            } footer: {
                Text("右键菜单没出现时，先确认「\(AppInfo.name)」在这里是开启状态。")
            }
            Section("配置与日志") {
                Text(AppPaths.configFile.path)
                Text(AppPaths.diagFile.path)
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .formStyle(.grouped)
        // 菜单栏开关：直接绑定在 Toggle 上，所以在这里同步驻留策略
        .onChange(of: config.showMenuBarIcon) { _, newValue in
            MenuBarVisibility.shared.isInserted = newValue
        }
        .fileImporter(isPresented: $choosingTerminal, allowedContentTypes: [.application]) { result in
            if case .success(let url) = result { config.terminalApp = url.path }
        }
    }
}

// MARK: - 工具箱

struct ToolsPane: View {
    @Binding var config: AppConfig

    private func toggle(_ tool: (key: String, title: String)) -> some View {
        Toggle(tool.title, isOn: Binding(
            get: { config.tool(tool.key) },
            set: { config.tools[tool.key] = $0 }
        ))
    }

    var body: some View {
        Form {
            Section("右键菜单里出现的单项功能") {
                ForEach(ToolKey.all, id: \.key) { tool in
                    toggle(tool)
                }
            }
            Section {
                ForEach(ToolKey.image, id: \.key) { tool in
                    toggle(tool)
                }
            } header: {
                Text("图片处理")
            } footer: {
                Text("这组功能只在选中的文件里有图片时才出现在右键菜单，不选图片不会看到。")
            }
            Section {
                Label("「彻底删除」不进废纸篓，点了就没了。", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 文件类型图标

/// 用系统真实图标（NSWorkspace 按 UTType 给的），不是自绘。
private func systemIcon(for ext: String) -> NSImage? {
    guard let type = UTType(filenameExtension: ext) else { return nil }
    return NSWorkspace.shared.icon(for: type)
}

private struct TypeIcon: View {
    let ext: String

    var body: some View {
        if let image = systemIcon(for: ext) {
            Image(nsImage: image).resizable().frame(width: 16, height: 16)
        } else {
            Image(systemName: "doc").frame(width: 16, height: 16).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 新建文件

struct FileTypesPane: View {
    @Binding var config: AppConfig

    var body: some View {
        Form {
            Section {
                ForEach($config.fileTypes) { $type in
                    HStack(spacing: 10) {
                        Toggle("", isOn: $type.enabled)
                            .labelsHidden()
                            .frame(width: 40, alignment: .leading)
                        TypeIcon(ext: type.ext)
                            .frame(width: 18)
                        TextField("", text: $type.displayName)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(width: 150)
                        TextField("", text: $type.ext)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 80)
                        Spacer(minLength: 12)
                    }
                }
                .onDelete { config.fileTypes.remove(atOffsets: $0) }
                .reorderable()
            } header: {
                Text("文件类型")
            } footer: {
                Text("只在这里出现的类型才会进右键菜单。拖动行可以调整顺序。")
            }

            Section {
                Button {
                    config.fileTypes.append(FileType(displayName: "新类型", ext: "txt", enabled: true))
                } label: {
                    Label("添加类型", systemImage: "plus")
                }
                .buttonStyle(.glass)
            }
        }
        .formStyle(.grouped)
        .reorderContainer(for: FileType.self) { difference in
            applyReorder(difference, to: &config.fileTypes)
        }
    }
}

// MARK: - 发送文件到 / 常用目录

enum DirectoryKind {
    case sendTo
    case common
}

struct DirectoryPane: View {
    @Binding var config: AppConfig
    let kind: DirectoryKind

    private var items: Binding<[Shortcut]> {
        switch kind {
        case .sendTo: return $config.sendToDirectories
        case .common: return $config.commonDirectories
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(items) { $entry in
                    HStack(spacing: 10) {
                        Toggle("", isOn: $entry.enabled)
                            .labelsHidden()
                            .frame(width: 40, alignment: .leading)
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.tint)
                            .frame(width: 18)
                        TextField("", text: $entry.displayName)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(width: 130)
                        TextField("", text: $entry.path)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 340)
                        Spacer(minLength: 12)
                    }
                }
                .onDelete { items.wrappedValue.remove(atOffsets: $0) }
                .reorderable()
            } header: {
                Text(kind == .sendTo ? "目标目录" : "常用目录")
            } footer: {
                Text(kind == .sendTo
                     ? "在「通用设置」里切换这两个动作是复制还是移动。拖动行可以调整顺序。"
                     : "点击后直接在访达里打开该目录。拖动行可以调整顺序。")
            }

            Section {
                Button {
                    let home = AppPaths.realHome
                    items.wrappedValue.append(Shortcut(displayName: "新目录",
                                                       path: home.appendingPathComponent("Desktop").path,
                                                       enabled: true))
                } label: {
                    Label("添加目录", systemImage: "plus")
                }
                .buttonStyle(.glass)
            }
        }
        .formStyle(.grouped)
        .reorderContainer(for: Shortcut.self) { difference in
            applyReorder(difference, to: &items.wrappedValue)
        }
    }
}
