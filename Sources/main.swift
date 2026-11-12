import AppKit
import Combine
import SwiftUI

enum AppInfo {
    static let repoURL = URL(string: "https://github.com/spacecakes/isofix")!
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let model = AppModel()
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var menuBarSetting: AnyCancellable?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.mainMenu = makeMainMenu()
        model.start()
        menuBarSetting = model.$showsInMenuBar.sink { [weak self] in self?.setStatusItem($0) }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.model.refresh()
        }

        if model.showsWindowAtLaunch { showWindow() }
    }

    /// Opening the app again while it's running (Finder, Spotlight, `open`) lands here.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: Window

    @objc func showAbout() {
        let credits = NSMutableAttributedString(
            string: "Keeps § and < in the right place on non-Apple ISO keyboards.\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        credits.append(NSAttributedString(string: AppInfo.repoURL.absoluteString, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .link: AppInfo.repoURL]))
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        credits.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }

    @objc func showWindow() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = "ISOFix" // still used by Mission Control and the Window menu
            w.titleVisibility = .hidden // the header already shows the name
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        model.refresh()
        model.recordsPresses = true
        // Show in Dock and ⌘-Tab only while the window is open.
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }

    func windowWillClose(_ notification: Notification) {
        model.recordsPresses = false
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: Menu bar

    private func setStatusItem(_ shown: Bool) {
        guard shown != (statusItem != nil) else { return }
        guard shown else {
            NSStatusBar.system.removeStatusItem(statusItem!)
            statusItem = nil
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarIcon.image
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Built on open, so keyboards and their state are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !model.monitoring {
            menu.addItem(withTitle: "Input Monitoring needed…", action: #selector(showWindow), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
        if model.rows.isEmpty {
            menu.addItem(withTitle: "No external keyboards", action: nil, keyEquivalent: "")
        }
        for row in model.rows {
            let item = NSMenuItem(title: row.name, action: nil, keyEquivalent: "")
            let status = switch row.mode {
            case .auto: row.swapApplied ? "Swapped by ISOFix" : "Automatic"
            case .swap: "Always swap"
            case .off: "Off"
            }
            if #available(macOS 14.4, *) { item.subtitle = status } else { item.title += " — \(status)" }
            item.submenu = modeMenu(for: row)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showWindow), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit ISOFix", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
    }

    /// Same choices as the window's picker.
    private func modeMenu(for row: AppModel.Row) -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ mode: AppModel.Mode) {
            let item = NSMenuItem(title: title, action: #selector(pickMode), keyEquivalent: "")
            item.target = self
            item.representedObject = ModeChoice(id: row.id, mode: mode)
            item.state = row.mode == mode ? .on : .off
            menu.addItem(item)
        }
        add("Automatic", .auto)
        menu.addItem(.separator())
        add("Always swap", .swap)
        add("Off", .off)
        return menu
    }

    private struct ModeChoice { let id: KeyboardID; let mode: AppModel.Mode }

    @objc private func pickMode(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? ModeChoice else { return }
        model.setMode(choice.mode, for: choice.id)
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ISOFix", action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit ISOFix", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        return main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
