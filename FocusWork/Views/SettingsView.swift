import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Pomodoro") {
                Stepper(value: $model.pomodoroSettings.workMinutes, in: 1...120) {
                    Text("Work: \(model.pomodoroSettings.workMinutes) min")
                }
                Stepper(value: $model.pomodoroSettings.shortBreakMinutes, in: 1...60) {
                    Text("Short break: \(model.pomodoroSettings.shortBreakMinutes) min")
                }
                Stepper(value: $model.pomodoroSettings.longBreakMinutes, in: 1...60) {
                    Text("Long break: \(model.pomodoroSettings.longBreakMinutes) min")
                }
                Stepper(value: $model.pomodoroSettings.sessionsUntilLongBreak, in: 1...10) {
                    Text("Sessions until long break: \(model.pomodoroSettings.sessionsUntilLongBreak)")
                }
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
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 380, minHeight: 360)
    }
}
