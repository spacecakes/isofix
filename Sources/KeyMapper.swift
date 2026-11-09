import Carbon.HIToolbox
import Foundation
import IOKit.hid
import IOKit.hidsystem

struct KeyboardID: Hashable, CustomStringConvertible {
    let vendor: Int
    let product: Int
    var description: String { String(format: "%04X:%04X", vendor, product) }
}

/// Display-only details; nothing here affects detection.
struct KeyboardInfo: Equatable {
    var manufacturer: String?
    var transport: String?
}

struct ExternalKeyboard {
    let id: KeyboardID
    let name: String
    var swapApplied: Bool
    var info = KeyboardInfo()
}

/// Reads and writes the per-device `UserKeyMapping` (same thing `hidutil` does),
/// merging our two entries with whatever else is already mapped on the device.
final class KeyMapper {
    /// Raw HID usage -> the virtual keycode it should produce on a PC ISO board:
    /// left of 1 -> § (kVK_ISO_Section), right of left Shift -> < (kVK_ANSI_Grave).
    static let expectedKeycode: [Int: Int64] = [
        kHIDUsage_KeyboardGraveAccentAndTilde: Int64(kVK_ISO_Section),
        kHIDUsage_KeyboardNonUSBackslash: Int64(kVK_ANSI_Grave),
    ]

    private static let grave = 0x7_0000_0000 | Int64(kHIDUsage_KeyboardGraveAccentAndTilde)
    private static let nonUSBackslash = 0x7_0000_0000 | Int64(kHIDUsage_KeyboardNonUSBackslash)
    private static let ourEntries: [(Int64, Int64)] = [(grave, nonUSBackslash), (nonUSBackslash, grave)]

    private var client: IOHIDEventSystemClient?


    /// Identity of a keyboard we should manage, or nil for Apple/built-in/virtual ones.
    /// `property` reads an IORegistry property from either an IOHIDDevice or a service client.
    static func eligibleID(_ property: (String) -> Any?) -> KeyboardID? {
        func num(_ k: String) -> Int? { (property(k) as? NSNumber)?.intValue }
        guard let vendor = num(kIOHIDVendorIDKey), let product = num(kIOHIDProductIDKey) else { return nil }
        let name = property(kIOHIDProductKey) as? String ?? ""
        // Apple keyboards (USB 0x05AC, Bluetooth 0x004C) and the built-in one are identified correctly.
        if num(kIOHIDBuiltInKey) ?? 0 != 0 || [0, 0x05AC, 0x004C].contains(vendor) { return nil }
        if name.localizedCaseInsensitiveContains("karabiner") { return nil }
        return KeyboardID(vendor: vendor, product: product)
    }

    private func services() -> [(id: KeyboardID, name: String, service: IOHIDServiceClient)] {
        // A fresh client every time: an unscheduled client keeps the service list it
        // started with, so keyboards plugged in later would never show up. Kept in a
        // property because the returned services crash if their client is freed.
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        self.client = client
        guard let all = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return [] }
        return all.compactMap { s in
            guard IOHIDServiceClientConformsTo(s, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard)) != 0
            else { return nil }
            let prop = { (k: String) in IOHIDServiceClientCopyProperty(s, k as CFString) }
            guard let id = Self.eligibleID(prop) else { return nil }
            let name = (prop(kIOHIDProductKey) as? String)?.trimmingCharacters(in: .whitespaces)
            return (id, name.flatMap { $0.isEmpty ? nil : $0 } ?? "Keyboard", s)
        }
    }

    private static func info(_ s: IOHIDServiceClient) -> KeyboardInfo {
        func str(_ k: String) -> String? {
            let v = (IOHIDServiceClientCopyProperty(s, k as CFString) as? String)?
                .trimmingCharacters(in: .whitespaces)
            return v?.isEmpty == false ? v : nil
        }
        return KeyboardInfo(manufacturer: str(kIOHIDManufacturerKey), transport: str(kIOHIDTransportKey))
    }

    private func mapping(_ s: IOHIDServiceClient) -> [[String: Any]] {
        IOHIDServiceClientCopyProperty(s, kIOHIDUserKeyUsageMapKey as CFString) as? [[String: Any]] ?? []
    }

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        guard let src = (entry[kIOHIDKeyboardModifierMappingSrcKey] as? NSNumber)?.int64Value,
              let dst = (entry[kIOHIDKeyboardModifierMappingDstKey] as? NSNumber)?.int64Value else { return false }
        return ourEntries.contains { $0 == (src, dst) }
    }

    private func isApplied(_ s: IOHIDServiceClient) -> Bool {
        mapping(s).filter(Self.isOurs).count == Self.ourEntries.count
    }

    /// One entry per board; a board can expose several keyboard services.
    func keyboards() -> [ExternalKeyboard] {
        var result: [ExternalKeyboard] = []
        for (id, name, s) in services() {
            if let i = result.firstIndex(where: { $0.id == id }) {
                result[i].swapApplied = result[i].swapApplied && isApplied(s)
            } else {
                result.append(ExternalKeyboard(id: id, name: name, swapApplied: isApplied(s),
                                               info: Self.info(s)))
            }
        }
        return result
    }

    func setSwap(_ on: Bool, for id: KeyboardID) {
        for (sid, _, s) in services() where sid == id {
            var m = mapping(s).filter { !Self.isOurs($0) }
            if on {
                m += Self.ourEntries.map {
                    [kIOHIDKeyboardModifierMappingSrcKey: NSNumber(value: $0.0),
                     kIOHIDKeyboardModifierMappingDstKey: NSNumber(value: $0.1)]
                }
            }
            IOHIDServiceClientSetProperty(s, kIOHIDUserKeyUsageMapKey as CFString, m as NSArray)
        }
    }
}
