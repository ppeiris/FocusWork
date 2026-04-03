import SwiftUI

struct FloatingTimerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var tasks: TaskStore
    @EnvironmentObject private var pomodoro: PomodoroEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(phaseTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(tasks.activeTask?.title ?? "No task selected")
                .font(.headline)
                .lineLimit(2)
                .foregroundStyle(.primary)

            Text(timeString)
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .monospacedDigit()

            HStack(spacing: 10) {
                Button(pomodoro.isRunning ? "Pause" : "Start") {
                    if pomodoro.isRunning {
                        pomodoro.pause()
                    } else {
                        pomodoro.startOrResume()
                    }
                }

                Button("Skip") {
                    pomodoro.skipPhase()
                }

                Button("Reset") {
                    pomodoro.resetSession()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            }
        }
        .padding(8)
    }

    private var phaseTitle: String {
        switch pomodoro.phase {
        case .idle: return "Ready"
        case .work: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }

    private var timeString: String {
        let s = max(0, pomodoro.remainingSeconds)
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}
