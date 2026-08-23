import SwiftData
import SwiftUI
import TipKit

@main
struct RemindyApp: App {
    private let container: ModelContainer

    init() {
        container = Self.makeContainer()
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }

    private static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: Reminder.self)
        } catch {
            let support = URL.applicationSupportDirectory
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: support.appending(path: "default.store\(suffix)"))
            }
            if let fresh = try? ModelContainer(for: Reminder.self) {
                return fresh
            }
            let memoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: Reminder.self, configurations: memoryConfig)
        }
    }
}
