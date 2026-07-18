import Foundation
import IOKit.hid

private let flowLiteVendorID = 0x05AC
private let flowLiteProductID = 0x024F
private let genericDesktopPage = 0x01
private let wheelUsage = 0x38
private let consumerPage = 0x0C
private let acPanUsage = 0x0238

private func label(page: UInt32, usage: UInt32) -> String {
    switch (page, usage) {
    case (UInt32(genericDesktopPage), UInt32(wheelUsage)):
        return "vertical-wheel"
    case (UInt32(consumerPage), UInt32(acPanUsage)):
        return "horizontal-pan"
    case (UInt32(consumerPage), 0x00E9):
        return "volume-up"
    case (UInt32(consumerPage), 0x00EA):
        return "volume-down"
    case (UInt32(consumerPage), 0x00E2):
        return "mute"
    case (0x09, 1...5):
        return "button-\(usage)"
    case (0x07, _):
        return String(format: "keyboard-usage-%02X", usage)
    case (UInt32(genericDesktopPage), 0x30):
        return "pointer-x"
    case (UInt32(genericDesktopPage), 0x31):
        return "pointer-y"
    default:
        return String(format: "page-%04X/usage-%04X", page, usage)
    }
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matching: [String: Any] = [
    kIOHIDVendorIDKey as String: flowLiteVendorID,
    kIOHIDProductIDKey as String: flowLiteProductID,
]

IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, device in
    let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "unknown"
    let page = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber
    let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? NSNumber
    print(String(
        format: "connected: %@ interface %04X:%04X",
        product,
        page?.uint32Value ?? 0,
        usage?.uint32Value ?? 0
    ))
}, nil)

IOHIDManagerRegisterInputValueCallback(manager, { _, result, _, value in
    guard result == kIOReturnSuccess else { return }
    let element = IOHIDValueGetElement(value)
    let page = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    let integerValue = IOHIDValueGetIntegerValue(value)

    guard integerValue != 0,
          (page == genericDesktopPage || page == consumerPage || page == 0x09 || page == 0x07) else {
        return
    }

    print("\(label(page: page, usage: usage)) value=\(integerValue)")
    fflush(stdout)
}, nil)

IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard openResult == kIOReturnSuccess else {
    fputs("Could not open the Flow Lite pointer interface (IOReturn \(openResult)). Check Input Monitoring permission.\n", stderr)
    exit(1)
}

let seconds = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 15
print("Listening read-only for \(seconds) seconds across all Flow Lite HID interfaces. Rotate the roller both ways; press it too if it clicks.")
CFRunLoopRunInMode(.defaultMode, seconds, false)
IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
