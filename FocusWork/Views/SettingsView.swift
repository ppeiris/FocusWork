import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Focus timer") {
                Stepper(value: $model.pomodoroSettings.workMinutes, in: 1...120) {
                    Text("Default work block: \(model.pomodoroSettings.workMinutes) min")
                }
                Text("Used when a task has no estimate. Breaks between sessions are off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Floating window") {
                Toggle("Always on top", isOn: $model.floatingAlwaysOnTop)

                VStack(alignment: .leading) {
                    Text("Opacity")
                    Slider(value: $model.floatingOpacity, in: 0.35 ... 1, step: 0.05)
                    Text("\(Int(model.floatingOpacity * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Obsidian Vault") {
                if let vaultURL = model.taskStore.vaultURL {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Vault")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(vaultURL.path)
                            .textSelection(.enabled)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    if let folderURL = model.taskStore.projectsFolderURL {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Projects Folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(folderURL.path)
                                .textSelection(.enabled)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }
                } else {
                    Text("No vault configured. Tasks are currently stored locally.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button("Choose Vault…") {
                        chooseVault()
                    }

                    if let vaultURL = model.taskStore.vaultURL {
                        Button("Open Vault") {
                            #if os(macOS)
                            NSWorkspace.shared.open(vaultURL)
                            #endif
                        }

                        Button("Clear") {
                            model.taskStore.configureVault(url: nil)
                        }
                    }
                }

                Text("Each project is written as `FocusWork/Projects/project_<project-name>.md`. Tasks use indented lines like `#fw/title …`, `#fw/est-min …` (older pipe-separated lines still load).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 380, minHeight: 360)
    }

    private func chooseVault() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Choose Obsidian Vault"
        panel.prompt = "Use Vault"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let selected = panel.url {
            model.taskStore.configureVault(url: selected)
        }
        #endif
    }
}
