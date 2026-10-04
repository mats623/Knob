import Cocoa

/// Intercepts the volume media keys (as sent by the Keychron knob) system-wide.
final class MediaKeyTap {
    enum Key { case up, down, mute }

    /// Called on key-down. `fine` is true when ⌥⇧ is held (quarter steps).
    var onKey: (Key, _ fine: Bool) -> Void = { _, _ in }
    /// Keys are only swallowed while this returns true; otherwise macOS handles them.
    var shouldIntercept: () -> Bool = { false }

    private var port: CFMachPort?

    var isRunning: Bool { port != nil }

    func start() -> Bool {
        if port != nil { return true }
        let systemDefined = CGEventMask(1 << 14) // NX_SYSDEFINED
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: systemDefined,
            callback: mediaKeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 // NX_SUBTYPE_AUX_CONTROL_BUTTONS
        else { return Unmanaged.passUnretained(event) }

        let code = (nsEvent.data1 & 0xFFFF_0000) >> 16
        let flags = nsEvent.data1 & 0xFFFF
        let isDown = (flags & 0xFF00) >> 8 == 0xA

        let key: Key
        switch Int32(code) {
        case NX_KEYTYPE_SOUND_UP: key = .up
        case NX_KEYTYPE_SOUND_DOWN: key = .down
        case NX_KEYTYPE_MUTE: key = .mute
        default: return Unmanaged.passUnretained(event)
        }
        guard shouldIntercept() else { return Unmanaged.passUnretained(event) }

        if isDown {
            let fine = nsEvent.modifierFlags.contains([.option, .shift])
            onKey(key, fine)
        }
        return nil
    }
}

private func mediaKeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
}
