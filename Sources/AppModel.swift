import AppKit
import Combine
import ServiceManagement

/// All state and behaviour; the settings window is just a view onto it.
final class AppModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        let id: KeyboardID
        let name: String
        let swapApplied: Bool
        let info: KeyboardInfo
        let status: String
        let mode: Mode
    }

    enum Mode: Hashable { case auto, swap, leave }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var monitoring = false
    @Published private(set) var permissionGranted = Detector.hasPermission
    @Published private(set) var launchAtLogin = AppModel.loginEnabled
    @Published private(set) var loginError: String?
    /// Without the window there is no visible sign the app needs anything or
    /// that it started working, so show it on first run, while monitoring can't
    /// run, and on the launch after a run where it couldn't: the "Quit & Reopen"
    /// after the Input Monitoring grant.
    private(set) var showsWindowAtLaunch = false

    private let mapper = KeyMapper()
    private let detector = Detector()
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var pendingReconcile: DispatchWorkItem?
    private static var loginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    private enum Status { case correct(Date), fixed(Date) }
    private var status: [KeyboardID: Status] = [:]
    private var cooldownUntil: [KeyboardID: Date] = [:]

    private var isFirstRun: Bool { !defaults.bool(forKey: "didOnboard") }

    func start() {
        let firstRun = isFirstRun
        let monitoringFailedLastRun = defaults.bool(forKey: "monitoringFailed")
        if firstRun {
            defaults.set(true, forKey: "didOnboard")
            // "Install and forget": start at login unless the user turns it off.
            setLaunchAtLogin(true)
        }

        detector.onVerdict = { [weak self] id, verdict in self?.handle(verdict, for: id) }
        detector.onDevicesChanged = { [weak self] in self?.scheduleReconcile() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleReconcile()
        }

        if !detector.start() { Detector.requestPermission() }
        // Safety net: re-assert mappings and pick up a late permission grant.
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
        showsWindowAtLaunch = firstRun || monitoringFailedLastRun || !monitoring
    }

    func refresh() {
        permissionGranted = Detector.hasPermission
        monitoring = detector.start()
        defaults.set(!monitoring, forKey: "monitoringFailed")
        launchAtLogin = Self.loginEnabled
        reconcile()
    }

    /// Device attach/wake: the event-system service shows up a beat after the
    /// IOHIDDevice, and several keyboards attach at once, so coalesce into one pass.
    private func scheduleReconcile() {
        pendingReconcile?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reconcile() }
        pendingReconcile = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    // MARK: Swap state

    private func wantedSwap(_ id: KeyboardID) -> Bool? { defaults.object(forKey: "swap.\(id)") as? Bool }
    /// Per-keyboard opt-out, e.g. for a board whose keycaps really are printed the other way round.
    private func ignored(_ id: KeyboardID) -> Bool { defaults.bool(forKey: "ignore.\(id)") }

    private func apply(_ on: Bool, _ id: KeyboardID) {
        mapper.setSwap(on, for: id)
        defaults.set(on, forKey: "swap.\(id)")
    }

    private func reconcile() {
        var kbs = mapper.keyboards()
        for i in kbs.indices {
            if let want = wantedSwap(kbs[i].id), want != kbs[i].swapApplied {
                mapper.setSwap(want, for: kbs[i].id)
                kbs[i].swapApplied = want
                Detector.log.info("\(kbs[i].id, privacy: .public): re-applied swap=\(want)")
            }
        }
        rebuildRows(kbs)
    }

    /// Rebuilds the published rows; pass `kbs` when already enumerated, and
    /// `changed` to patch one board's swap state without re-reading IOKit.
    private func rebuildRows(_ kbs: [ExternalKeyboard]? = nil, changed: (KeyboardID, Bool)? = nil) {
        let boards = kbs ?? rows.map { ExternalKeyboard(id: $0.id, name: $0.name, swapApplied: $0.swapApplied, info: $0.info) }
        let new = boards.map { kb -> Row in
            let swap = changed?.0 == kb.id ? changed!.1 : kb.swapApplied
            func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
            let mode: Mode = ignored(kb.id) ? (swap ? .swap : .leave) : .auto
            let text: String
            switch status[kb.id] {
            case _ where mode != .auto, nil: text = ""
            case .correct(let d): text = "Correct, checked \(time(d))"
            case .fixed(let d): text = "Fixed at \(time(d))"
            }
            return Row(id: kb.id, name: kb.name, swapApplied: swap, info: kb.info, status: text, mode: mode)
        }
        if new != rows { rows = new }
    }

    /// Automatic keeps the current swap until the next keypress proves it wrong;
    /// the manual modes pin it and stop detection for that keyboard.
    func setMode(_ mode: Mode, for id: KeyboardID) {
        defaults.set(mode != .auto, forKey: "ignore.\(id)")
        status[id] = nil
        var changed: (KeyboardID, Bool)?
        if mode != .auto {
            apply(mode == .swap, id)
            changed = (id, mode == .swap)
        }
        rebuildRows(changed: changed)
    }

    private func handle(_ verdict: Detector.Verdict, for id: KeyboardID) {
        if ignored(id) { return }
        if let until = cooldownUntil[id], until > Date() { return }
        var changed: (KeyboardID, Bool)?
        switch verdict {
        case .correct:
            status[id] = .correct(Date())
        case .wrong:
            guard let row = rows.first(where: { $0.id == id }) else { return }
            let on = !row.swapApplied
            apply(on, id)
            changed = (id, on)
            cooldownUntil[id] = Date().addingTimeInterval(1)
            status[id] = .fixed(Date())
            Detector.log.notice("\(id, privacy: .public): wrong key detected, swap now \(on)")
        }
        rebuildRows(changed: changed)
    }

    // MARK: Settings

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = Self.loginEnabled
    }

    func requestPermission() {
        Detector.requestPermission()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
}
