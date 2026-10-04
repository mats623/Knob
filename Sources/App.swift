import Cocoa
import SwiftUI

@main
struct KnobApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = VolumeController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(controller)
        } label: {
            Image(systemName: "speaker.wave.3.fill", variableValue: controller.muted ? 0 : controller.volume)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        VolumeController.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        VolumeController.shared.shutdown()
    }
}

struct MenuView: View {
    @EnvironmentObject private var controller: VolumeController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(spacing: 10) {
                Button { controller.toggleMute() } label: {
                    Image(systemName: speakerSymbol(volume: controller.volume, muted: controller.muted))
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 20, height: 20)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)

                Slider(value: Binding(get: { controller.volume }, set: { controller.setVolume($0) }), in: 0...1)
                    .controlSize(.small)

                Text("\(Int((controller.volume * 100).rounded()))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .trailing)
            }
            .disabled(!controller.isActive)
            .opacity(controller.isActive ? 1 : 0.4)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Methode")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("Methode", selection: $controller.method) {
                    ForEach(ControlMethod.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle("Bei Anmeldung öffnen", isOn: $controller.launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 12))

            if !controller.accessibilityGranted {
                Button { controller.openAccessibilitySettings() } label: {
                    Label("Bedienungshilfen-Zugriff erlauben", systemImage: "exclamationmark.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.link)
            }

            Divider()

            HStack {
                Text("Knob")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Beenden") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 290)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.deviceName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var statusText: String {
        switch controller.backend {
        case .detecting: "Suche Monitor …"
        case .system: "macOS regelt die Lautstärke selbst"
        case .monitor: "Lautstärke wird am Monitor gesetzt"
        case .software: "Lautstärke wird per Software geregelt"
        case let .unavailable(reason): reason
        }
    }

    private var statusColor: Color {
        switch controller.backend {
        case .monitor, .software: .green
        case .system, .detecting: .secondary.opacity(0.5)
        case .unavailable: .orange
        }
    }
}
