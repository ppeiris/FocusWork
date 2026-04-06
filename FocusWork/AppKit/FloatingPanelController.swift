import AppKit
import SwiftUI

final class FloatingPanelController: NSObject {
    static let shared = FloatingPanelController()

    private var panel: FloatingPanel?
    /// Fixed content width; height follows measured SwiftUI content (clamped to the screen).
    private let panelContentWidth: CGFloat = 340
    private let minPanelHeight: CGFloat = 220
    private var lastAppliedContentHeight: CGFloat = 0

    private override init() {
        super.init()
    }

    /// Vertical limit for panel content so the window stays on-screen; `ScrollView` handles overflow inside.
    private func maxContentHeightForScreen(using panel: NSWindow) -> CGFloat {
        let screen = panel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame.height ?? 900
        return max(minPanelHeight + 40, visible - 48)
    }

    /// Called from `FloatingTimerView` when its layout size changes so the panel grows or shrinks with the task list.
    func applyReportedContentHeight(_ height: CGFloat) {
        guard let panel else { return }
        guard height.isFinite, height > 80 else { return }
        let screenMax = maxContentHeightForScreen(using: panel)
        let clamped = min(max(height, minPanelHeight), screenMax)
        guard abs(clamped - lastAppliedContentHeight) > 1.5 else { return }
        lastAppliedContentHeight = clamped
        let newSize = NSSize(width: panelContentWidth, height: clamped)
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel else { return }
            let cap = self.maxContentHeightForScreen(using: panel)
            panel.maxSize = NSSize(width: self.panelContentWidth, height: cap)
            panel.setContentSize(newSize)
        }
    }

    func configureIfNeeded(model: AppModel) {
        if panel == nil {
            let initialSize = NSSize(width: panelContentWidth, height: 360)
            let p = FloatingPanel(
                contentRect: NSRect(x: 80, y: 80, width: initialSize.width, height: initialSize.height),
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
            p.setContentSize(initialSize)
            p.minSize = NSSize(width: panelContentWidth, height: minPanelHeight)
            p.maxSize = NSSize(width: panelContentWidth, height: maxContentHeightForScreen(using: p))

            self.panel = p
            lastAppliedContentHeight = initialSize.height
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
            .environmentObject(model.taskStore)
            .environmentObject(model.pomodoro)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
