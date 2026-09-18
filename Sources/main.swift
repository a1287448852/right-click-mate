import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        var config = AppConfig.load()
        if config.pendingCut.isEmpty && !FileManager.default.fileExists(atPath: AppPaths.configFile.path) {
            config = .standard
        }
        config.save()

        let controller = SettingsWindowController(config: config)
        controller.showWindow(nil)
        windowController = controller
        NSApp.activate(ignoringOtherApps: true)

        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("SuperRightClickShowInfo"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.showFileInfo()
        }

        if CommandLine.arguments.contains("--show-info") {
            showFileInfo()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func showFileInfo() {
        guard let text = try? String(contentsOf: AppPaths.lastInfoFile, encoding: .utf8) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "文件信息"
        alert.informativeText = text
        alert.addButton(withTitle: "关闭")
        alert.runModal()
    }
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
