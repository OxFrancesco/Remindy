import Foundation
import SwiftData

enum Recurrence: String, Codable, CaseIterable, Identifiable {
    case none = "none"
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "Never"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    func next(after date: Date) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        }
    }
}

enum PlaceTrigger: String, Codable, CaseIterable, Identifiable {
    case onEntry
    case onExit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onEntry: "When I Arrive"
        case .onExit: "When I Leave"
        }
    }
}

@Model
final class Reminder {
    var title: String = ""
    var note: String = ""
    var createdAt: Date = Date.now
    var completedAt: Date?
    var dueDate: Date?
    var recurrenceRaw: String = Recurrence.none.rawValue
    var isArchived: Bool = false
    var isLogger: Bool = false
    var tagID: String?
    var latitude: Double?
    var longitude: Double?
    var radiusMeters: Double = 150
    var placeName: String = ""
    var placeTriggerRaw: String = PlaceTrigger.onEntry.rawValue
    var regionID: String?
    var parent: Reminder?
    @Relationship(deleteRule: .cascade, inverse: \Reminder.parent)
    var subtasks: [Reminder] = []
    var log: [Date] = []

    init(title: String, note: String = "", dueDate: Date? = nil, recurrence: Recurrence = .none, isLogger: Bool = false) {
        self.title = title
        self.note = note
        self.createdAt = .now
        self.completedAt = nil
        self.dueDate = dueDate
        self.recurrenceRaw = recurrence.rawValue
        self.isArchived = false
        self.isLogger = isLogger
    }

    var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }

    var placeTrigger: PlaceTrigger {
        get { PlaceTrigger(rawValue: placeTriggerRaw) ?? .onEntry }
        set { placeTriggerRaw = newValue.rawValue }
    }

    var hasPlace: Bool { latitude != nil && longitude != nil }

    var needsPlaceWatch: Bool {
        hasPlace && !isArchived && completedAt == nil && regionID != nil
    }

    func clearPlace() {
        latitude = nil
        longitude = nil
        placeName = ""
        regionID = nil
    }

    func ensureRegionID() {
        if regionID == nil { regionID = UUID().uuidString }
    }

    var isDone: Bool { completedAt != nil }

    // A recurring task stays checked until its next period elapses.
    var isCurrentlyDone: Bool {
        if isLogger { return false }
        guard let completedAt else { return false }
        guard recurrence != .none else { return true }
        guard let next = recurrence.next(after: completedAt) else { return true }
        return next > .now
    }

    var lastLogged: Date? {
        log.last
    }

    var isOverdue: Bool {
        guard !isCurrentlyDone, let dueDate else { return false }
        return dueDate < .now
    }

    var subtaskProgress: String? {
        guard !subtasks.isEmpty else { return nil }
        let done = subtasks.filter(\.isCurrentlyDone).count
        return "\(done)/\(subtasks.count)"
    }

    func complete() {
        if isLogger {
            log.append(.now)
            return
        }
        guard !isCurrentlyDone else { return }
        let now = Date.now
        completedAt = now
        log.append(now)
        if recurrence != .none, let dueDate, let next = recurrence.next(after: max(dueDate, .now)) {
            self.dueDate = next
        }
    }

    func uncomplete() {
        if let completedAt, let last = log.last,
           abs(last.timeIntervalSince(completedAt)) < 0.5 {
            log.removeLast()
        }
        completedAt = nil
    }

    func toggleComplete() {
        isCurrentlyDone ? uncomplete() : complete()
    }
}

extension Calendar {
    func startOfMonth(for date: Date = .now) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
