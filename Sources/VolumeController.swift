import ApplicationServices
import Cocoa
import CoreAudio
import ServiceManagement

enum ControlMethod: String, CaseIterable, Identifiable {
    case auto, monitor, software

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .monitor: "Monitor"
        case .software: "Software"
        }
    }
}

enum Backend: Equatable {
    /// Still figuring out what to do.
    case detecting
    /// The output has its own volume control — macOS handles the keys.
    case system
    /// Volume is set on the monitor via DDC/CI.
    case monitor
    /// Volume is applied in software before audio reaches the output.
    case software
    case unavailable(String)
}

final class VolumeController: ObservableObject {
    static let shared = VolumeController()

    @Published private(set) var volume: Double = 0.5
    @Published private(set) var muted = false
    @Published private(set) var backend: Backend = .detecting
    @Published private(set) var deviceName = "—"
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published var method: ControlMethod {
        didSet {
            guard method != oldValue else { return }
            defaults.set(method.rawValue, forKey: "method")
            evaluate()
        }
    }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    var isActive: Bool { backend == .monitor || backend == .software }

    private let defaults = UserDefaults.standard
    private let keyTap = MediaKeyTap()
    private let software = SoftwareVolume()
    private let ddcQueue = DispatchQueue(label: "knob.ddc", qos: .userInitiated)
    private let ddcLock = NSLock()
    private var ddcDisplay: DDCDisplay?
    private var ddcMax = 100
    private var ddcPending: Int?
    private var ddcWriting = false
    private var generation = 0
    private var evaluateWork: DispatchWorkItem?

    private init() {
        method = ControlMethod(rawValue: defaults.string(forKey: "method") ?? "") ?? .auto
    }

    // MARK: Lifecycle

    func start() {
        keyTap.shouldIntercept = { [weak self] in self?.isActive ?? false }
        keyTap.onKey = { [weak self] key, fine in self?.handle(key, fine: fine) }
        startKeyTap()

        AudioDevices.observeDefaultOutput { [weak self] in self?.scheduleEvaluate() }
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleEvaluate(after: 1.5)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleEvaluate(after: 2)
        }
        evaluate()
    }

    func shutdown() {
        software.stop()
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func startKeyTap() {
        if keyTap.start() {
            accessibilityGranted = true
            return
        }
        accessibilityGranted = false
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            if AXIsProcessTrusted(), self.keyTap.start() {
                self.accessibilityGranted = true
                timer.invalidate()
            }
        }
    }

    // MARK: Backend selection

    private func scheduleEvaluate(after delay: TimeInterval = 0.3) {
        evaluateWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluate() }
        evaluateWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func evaluate() {
        generation += 1
        let current = generation
        let device = AudioDevices.defaultOutput()
        deviceName = AudioDevices.name(device) ?? "Unbekanntes Gerät"

        if method == .auto && AudioDevices.hasVolumeControl(device) {
            use(.system, device: device)
            return
        }
        if method == .software {
            use(.software, device: device)
            return
        }

        backend = .detecting
        ddcQueue.async { [weak self] in
            let found = DDCDisplay.externalDisplays().lazy
                .compactMap { display in display.read(DDCDisplay.volumeCode).map { (display, $0) } }
                .first
            DispatchQueue.main.async {
                guard let self, current == self.generation else { return }
                if let (display, value) = found {
                    self.ddcDisplay = display
                    self.ddcMax = value.max
                    if !self.muted || value.current > 0 {
                        self.volume = Double(value.current) / Double(value.max)
                        self.muted = false
                    }
                    self.use(.monitor, device: device)
                } else if self.method == .auto {
                    self.use(.software, device: device)
                } else {
                    self.use(.unavailable("Monitor antwortet nicht auf DDC/CI"), device: device)
                }
            }
        }
    }

    private func use(_ newBackend: Backend, device: AudioDeviceID) {
        if newBackend != .software {
            software.stop()
        } else if !(software.isRunning && software.device == device) {
            volume = defaults.object(forKey: "softwareVolume") as? Double ?? 0.5
            muted = false
            do {
                try software.start(outputDevice: device)
            } catch {
                backend = .unavailable(error.localizedDescription)
                return
            }
        }
        backend = newBackend
        if newBackend == .software { apply() }
    }

    // MARK: Volume

    private func handle(_ key: MediaKeyTap.Key, fine: Bool) {
        let step = fine ? 1.0 / 64 : 1.0 / 16
        switch key {
        case .up: setVolume((volume / step).rounded() * step + step)
        case .down: setVolume((volume / step).rounded() * step - step)
        case .mute: toggleMute()
        }
        HUD.shared.show(volume: volume, muted: muted)
    }

    func setVolume(_ value: Double) {
        guard isActive else { return }
        volume = min(1, max(0, value))
        muted = false
        apply()
    }

    func toggleMute() {
        guard isActive else { return }
        muted.toggle()
        apply()
    }

    private func apply() {
        switch backend {
        case .software:
            // Squared curve feels closer to how loudness is perceived.
            software.gain = muted ? 0 : Float(volume * volume)
            defaults.set(volume, forKey: "softwareVolume")
        case .monitor:
            writeDDC(muted ? 0 : Int((volume * Double(ddcMax)).rounded()))
        default:
            break
        }
    }

    /// DDC writes are slow, so only the latest requested value is sent while the knob turns.
    private func writeDDC(_ value: Int) {
        guard let display = ddcDisplay else { return }
        ddcLock.lock()
        ddcPending = value
        let shouldStart = !ddcWriting
        ddcWriting = true
        ddcLock.unlock()
        guard shouldStart else { return }

        ddcQueue.async { [weak self] in
            guard let self else { return }
            while true {
                self.ddcLock.lock()
                guard let next = self.ddcPending else {
                    self.ddcWriting = false
                    self.ddcLock.unlock()
                    return
                }
                self.ddcPending = nil
                self.ddcLock.unlock()
                display.write(DDCDisplay.volumeCode, next)
            }
        }
    }
}
