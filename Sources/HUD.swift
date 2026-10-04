import Cocoa
import SwiftUI

private final class HUDModel: ObservableObject {
    @Published var volume: Double = 0
    @Published var muted = false
}

/// Small volume overlay shown while turning the knob.
final class HUD {
    static let shared = HUD()

    private let model = HUDModel()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(volume: Double, muted: Bool) {
        model.volume = volume
        model.muted = muted

        let panel = self.panel ?? makePanel()
        self.panel = panel

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 96))
        }

        if !panel.isVisible || panel.alphaValue < 1 {
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                panel.animator().alphaValue = 0
            }, completionHandler: {
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: work)
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 260, height: 64)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.alphaValue = 0

        let host = NSHostingView(rootView: HUDView().environmentObject(model))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        return panel
    }
}

private struct HUDView: View {
    @EnvironmentObject var model: HUDModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: speakerSymbol(volume: model.volume, muted: model.muted))
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 22)
                .contentTransition(.symbolEffect(.replace))

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.12))
                    Capsule()
                        .fill(.primary.opacity(model.muted ? 0.3 : 0.9))
                        .frame(width: geometry.size.width * model.volume)
                }
            }
            .frame(height: 6)

            Text("\(Int((model.volume * 100).rounded()))")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .frame(width: 236, height: 46)
        .glassBackground(cornerRadius: 23)
        .animation(.smooth(duration: 0.15), value: model.volume)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

func speakerSymbol(volume: Double, muted: Bool) -> String {
    if muted || volume == 0 { return "speaker.slash.fill" }
    if volume < 0.34 { return "speaker.wave.1.fill" }
    if volume < 0.67 { return "speaker.wave.2.fill" }
    return "speaker.wave.3.fill"
}

extension View {
    @ViewBuilder
    func glassBackground(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
    }
}
