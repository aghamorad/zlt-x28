import SwiftUI
import AppKit
import Combine

@main
enum ZLTX28App {
    static var delegate: AppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        ZLTX28App.delegate = delegate
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
                         NSMenuDelegate {
    private let model = AppModel.shared
    private var window: NSWindow?
    private var statusItem: NSStatusItem!
    private var cancellable: AnyCancellable?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenuBar()
        buildWindow()
        NSApp.activate(ignoringOtherApps: true)

        cancellable = model.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.updateIcon(on: status.isOn) }

        timer = Timer.scheduledTimer(timeInterval: 45, target: self,
                                     selector: #selector(periodicRefresh),
                                     userInfo: nil, repeats: true)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { await self.model.refresh() }
        }

        Task { await model.refresh() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: - Window

    private func buildWindow() {
        let root = RootView().environmentObject(model)
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "ZLT X28"
        window.contentViewController = controller
        // The hosting view spans the whole window, under the floating toolbar.
        // Without this inset SwiftUI draws the page title in the toolbar's glass.
        controller.view.additionalSafeAreaInsets =
            NSEdgeInsets(top: 46, left: 0, bottom: 0, right: 0)
        window.minSize = NSSize(width: 900, height: 620)
        window.setFrameAutosaveName("ZLTX28MainWindow")
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func periodicRefresh() {
        guard window?.isVisible == true else { return }
        Task { await model.refresh() }
    }

    @objc private func showWindow() {
        if window == nil { buildWindow() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu bar

    private func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon(on: false)
    }

    private func updateIcon(on: Bool) {
        let name = on ? "lock.shield.fill" : "lock.open"
        if let image = NSImage(systemSymbolName: name,
                               accessibilityDescription: "ZLT X28") {
            image.isTemplate = true
            statusItem?.button?.image = image
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let headline: String
        if model.reach == .unreachable {
            headline = "Router not reachable"
        } else if model.vpnOn {
            headline = "VPN is on"
        } else {
            headline = "VPN is off"
        }
        let heading = NSMenuItem(title: headline, action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        let detail: String
        if model.reach == .unreachable {
            detail = "Join the X28's Wi-Fi"
        } else if model.vpnOn {
            detail = "Exit \(model.status.exitIP) · \(model.currentConfig)"
        } else {
            detail = "\(model.carrier.shortOperator) · \(model.carrier.networkType)"
        }
        let subheading = NSMenuItem(title: detail, action: nil, keyEquivalent: "")
        subheading.isEnabled = false
        menu.addItem(subheading)
        menu.addItem(.separator())

        let working = model.busy != nil || model.setupRunning
        let on = NSMenuItem(title: "Turn VPN On", action: #selector(turnOn),
                            keyEquivalent: "")
        on.target = self
        on.isEnabled = !working && model.provisioned && !model.vpnOn
        menu.addItem(on)

        let off = NSMenuItem(title: "Turn VPN Off", action: #selector(turnOff),
                             keyEquivalent: "")
        off.target = self
        off.isEnabled = !working && model.vpnOn
        menu.addItem(off)

        let restart = NSMenuItem(title: "Restart Tunnel", action: #selector(restart),
                                 keyEquivalent: "")
        restart.target = self
        restart.isEnabled = !working && model.provisioned
        menu.addItem(restart)

        menu.addItem(.separator())

        let configs = NSMenuItem(title: "Config", action: nil, keyEquivalent: "")
        let configMenu = NSMenu()
        for entry in model.configs {
            let item = NSMenuItem(title: entry.name,
                                  action: #selector(chooseConfig(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = entry.name
            item.state = entry.name == model.currentConfig ? .on : .off
            item.isEnabled = !working && entry.name != model.currentConfig
            configMenu.addItem(item)
        }
        if model.configs.isEmpty {
            let none = NSMenuItem(title: "No configs yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            configMenu.addItem(none)
        }
        configs.submenu = configMenu
        menu.addItem(configs)

        let open = NSMenuItem(title: "Open ZLT X28", action: #selector(showWindow),
                              keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())
        let credit = NSMenuItem(title: "Made by Morad", action: nil, keyEquivalent: "")
        credit.isEnabled = false
        menu.addItem(credit)

        let quit = NSMenuItem(title: "Quit ZLT X28", action: #selector(quit),
                              keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func turnOn() { Task { await model.turnOn() } }
    @objc private func turnOff() { Task { await model.turnOff() } }
    @objc private func restart() { Task { await model.restartTunnel() } }
    @objc private func chooseConfig(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        Task { await model.useConfig(name) }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
