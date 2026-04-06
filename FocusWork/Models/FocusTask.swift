import Foundation

enum FocusTaskPriority: String, Codable, CaseIterable {
    case urgent
    case next
    case later
}

enum FocusProjectCardColor: String, Codable, CaseIterable {
    case gray
    case blue
    case green
    case orange
    case pink
}

struct FocusProject: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var cardColor: FocusProjectCardColor
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        cardColor: FocusProjectCardColor = .gray,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.cardColor = cardColor
        self.sortOrder = sortOrder
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case cardColor
        case sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        cardColor = try container.decodeIfPresent(FocusProjectCardColor.self, forKey: .cardColor) ?? .gray
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(cardColor, forKey: .cardColor)
        try container.encode(sortOrder, forKey: .sortOrder)
    }
}

struct FocusTask: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var createdAt: Date
    var priority: FocusTaskPriority
    var projectId: UUID?
    /// Optional estimated time to complete, in minutes.
    var estimatedMinutes: Int?
    /// Saved work countdown (seconds) when paused mid-session; `nil` = start fresh from estimate or default.
    var savedWorkRemainingSeconds: Int?
    /// Cumulative seconds spent in focus on this task (persisted to vault).
    var totalFocusedSeconds: Int
    /// True when the task reached the end of its focus countdown.
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        priority: FocusTaskPriority = .later,
        projectId: UUID? = nil,
        estimatedMinutes: Int? = nil,
        savedWorkRemainingSeconds: Int? = nil,
        totalFocusedSeconds: Int = 0,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.priority = priority
        self.projectId = projectId
        self.estimatedMinutes = estimatedMinutes
        self.savedWorkRemainingSeconds = savedWorkRemainingSeconds
        self.totalFocusedSeconds = totalFocusedSeconds
        self.isCompleted = isCompleted
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case priority
        case projectId
        case estimatedMinutes
        case savedWorkRemainingSeconds
        case totalFocusedSeconds
        case isCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        priority = try container.decodeIfPresent(FocusTaskPriority.self, forKey: .priority) ?? .later
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
        estimatedMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        savedWorkRemainingSeconds = try container.decodeIfPresent(Int.self, forKey: .savedWorkRemainingSeconds)
        totalFocusedSeconds = try container.decodeIfPresent(Int.self, forKey: .totalFocusedSeconds) ?? 0
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(priority, forKey: .priority)
        try container.encodeIfPresent(projectId, forKey: .projectId)
        try container.encodeIfPresent(estimatedMinutes, forKey: .estimatedMinutes)
        try container.encodeIfPresent(savedWorkRemainingSeconds, forKey: .savedWorkRemainingSeconds)
        try container.encode(totalFocusedSeconds, forKey: .totalFocusedSeconds)
        try container.encode(isCompleted, forKey: .isCompleted)
    }
}
