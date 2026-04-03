import AppKit
import SwiftUI

final class FloatingPanelController: NSObject {
    static let shared = FloatingPanelController()

    private var panel: FloatingPanel?

    private override init() {
        super.init()
    }

    func configureIfNeeded(model: AppModel) {
        if panel == nil {
            let p = FloatingPanel(
                contentRect: NSRect(x: 80, y: 80, width: 320, height: 168),
                styleMask: [.nonactivatingPanel, .borderless, .resizable],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            p.level = NSWindow.Level.floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isMovableByWindowBackground = true
            p.titlebarAppearsTransparent = true
            p.titleVisibility = NSWindow.TitleVisibility.hidden
            p.backgroundColor = NSColor.clear
            p.isOpaque = false
            p.hasShadow = true
            p.hidesOnDeactivate = false

            let root = FloatingTimerRoot(model: model)
            let host = NSHostingController(rootView: root)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            p.contentViewController = host
            p.setContentSize(NSSize(width: 320, height: 168))

            self.panel = p
        }
        applyLevel(for: model.floatingAlwaysOnTop)
        setOpacity(model.floatingOpacity)
        panel?.orderFrontRegardless()
    }

    func setAlwaysOnTop(_ onTop: Bool) {
        applyLevel(for: onTop)
    }

    func setOpacity(_ value: Double) {
        panel?.alphaValue = CGFloat(value)
    }

    private func applyLevel(for onTop: Bool) {
        panel?.level = onTop ? NSWindow.Level.floating : NSWindow.Level.normal
    }
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct FloatingTimerRoot: View {
    @ObservedObject var model: AppModel

    var body: some View {
        FloatingTimerView()
            .environmentObject(model)
            .environmentObject(model.taskStore)
            .environmentObject(model.pomodoro)
    }
}
