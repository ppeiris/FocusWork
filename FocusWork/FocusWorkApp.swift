import AppKit
import SwiftUI

@main
struct FocusWorkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindowView()
                .environmentObject(model)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About FocusWork") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }

            CommandMenu("Timer") {
                Button("Start / Pause") {
                    toggleTimer()
                }
                .keyboardShortcut(.space, modifiers: [.command])

                Button("Skip phase") {
                    model.pomodoro.skipPhase()
                }
                .keyboardShortcut("s", modifiers: [.command])

                Button("Reset session") {
                    model.pomodoro.resetSession()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            CommandMenu("Window") {
                Button("Show floating timer") {
                    FloatingPanelController.shared.configureIfNeeded(model: model)
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
            }
        }

        MenuBarExtra("FocusWork", image: "MenuBarIcon") {
            MenuBarExtraMenuView()
                .environmentObject(model)
                .environmentObject(model.pomodoro)
        }
    }

    private func toggleTimer() {
        if model.pomodoro.isRunning {
            model.pomodoro.pause()
        } else {
            model.pomodoro.startOrResume()
        }
    }
}
