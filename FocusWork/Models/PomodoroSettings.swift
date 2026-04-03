import Foundation

struct PomodoroSettings: Codable, Equatable {
    var workMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    var sessionsUntilLongBreak: Int

    static let `default` = PomodoroSettings(
        workMinutes: 25,
        shortBreakMinutes: 5,
        longBreakMinutes: 15,
        sessionsUntilLongBreak: 4
    )

    var workSeconds: Int { max(1, workMinutes) * 60 }
    var shortBreakSeconds: Int { max(1, shortBreakMinutes) * 60 }
    var longBreakSeconds: Int { max(1, longBreakMinutes) * 60 }
}
