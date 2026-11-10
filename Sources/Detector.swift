import AppKit
import IOKit.hid
import os

/// Watches what the keyboard physically sends (raw HID usage, before macOS remaps it)
/// and what macOS turns it into (virtual keycode), and reports whether the
/// § / < keys came out right (see `KeyMapper.expectedKeycode`).
final class Detector {
    enum Verdict { case correct, wrong }

    /// The two watched keys, by where they sit on an ISO keyboard.
    enum Key {
        case leftOfOne, besideShift
        var label: String { self == .leftOfOne ? "§" : "<" }
    }

    /// One press of a watched key: the key the board reported and the key macOS typed.
    struct Check {
        let id: KeyboardID
        let pressed: Key
        let typed: Key
        var verdict: Verdict { pressed == typed ? .correct : .wrong }
    }

    var onCheck: ((Check) -> Void)?
    var onDevicesChanged: (() -> Void)?

    static let log = Logger(subsystem: "com.gabriellundmark.isofix", category: "detector")

    private static let expected = KeyMapper.expectedKeycode
    private static let watchedKeycodes = Set(expected.values)
    private static let window: TimeInterval = 0.15

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var tap: CFMachPort?
    private(set) var running = false

    private struct RawPress { let usage: Int; let id: KeyboardID?; let t: TimeInterval }
    private struct KeyPress { let code: Int64; let t: TimeInterval }
    private var raws: [RawPress] = []
    private var keys: [KeyPress] = []

    static var hasPermission: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func requestPermission() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    init() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ] as CFDictionary)
        // Only wake up for the two keys we care about, not every keystroke.
        IOHIDManagerSetInputValueMatchingMultiple(manager, Self.expected.keys.map {
            [kIOHIDElementUsagePageKey: kHIDPage_KeyboardOrKeypad, kIOHIDElementUsageKey: $0]
        } as CFArray)
        let devicesChanged: IOHIDDeviceCallback = { ctx, _, _, _ in
            Unmanaged<Detector>.fromOpaque(ctx!).takeUnretainedValue().onDevicesChanged?()
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, devicesChanged, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, devicesChanged, ctx)
        IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
            Unmanaged<Detector>.fromOpaque(ctx!).takeUnretainedValue().handleRaw(value)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    /// Returns false if Input Monitoring hasn't been granted yet.
    @discardableResult
    func start() -> Bool {
        if running { return true }
        guard Self.hasPermission else { return false }

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, ctx in
                let me = Unmanaged<Detector>.fromOpaque(ctx!).takeUnretainedValue()
                me.handleTap(type, event)
                return Unmanaged.passUnretained(event)
            }, userInfo: ctx)
        else {
            Self.log.error("event tap creation failed")
            return false
        }
        let rc = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard rc == kIOReturnSuccess else {
            Self.log.error("IOHIDManagerOpen failed: \(rc)")
            CFMachPortInvalidate(tap)
            return false
        }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        running = true
        Self.log.info("detector running")
        return true
    }

    private func handleRaw(_ value: IOHIDValue) {
        let el = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(el) == UInt32(kHIDPage_KeyboardOrKeypad),
              IOHIDValueGetIntegerValue(value) == 1 else { return }
        let usage = Int(IOHIDElementGetUsage(el))
        guard Self.expected[usage] != nil else { return }

        let dev = IOHIDElementGetDevice(el)
        // Non-eligible boards are still queued (id nil) so their keystrokes can't be
        // mistaken for an external board's.
        let id = KeyMapper.eligibleID { IOHIDDeviceGetProperty(dev, $0 as CFString) }

        raws.append(RawPress(usage: usage, id: id, t: ProcessInfo.processInfo.systemUptime))
        correlate()
    }

    private func handleTap(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        guard Self.watchedKeycodes.contains(code) else { return }
        keys.append(KeyPress(code: code, t: ProcessInfo.processInfo.systemUptime))
        correlate()
    }

    private func correlate() {
        let now = ProcessInfo.processInfo.systemUptime
        raws.removeAll { now - $0.t > Self.window }
        keys.removeAll { now - $0.t > Self.window }
        while !raws.isEmpty, !keys.isEmpty {
            let raw = raws.removeFirst(), key = keys.removeFirst()
            guard let id = raw.id else { continue }
            let section = kHIDUsage_KeyboardGraveAccentAndTilde
            let check = Check(id: id,
                              pressed: raw.usage == section ? .leftOfOne : .besideShift,
                              typed: key.code == Self.expected[section] ? .leftOfOne : .besideShift)
            Self.log.info("\(id, privacy: .public): usage 0x\(String(raw.usage, radix: 16), privacy: .public) -> keycode \(key.code) = \(check.verdict == .correct ? "correct" : "WRONG", privacy: .public)")
            onCheck?(check)
        }
    }
}
