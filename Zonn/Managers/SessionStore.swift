import Foundation
import SwiftData
import os.log

/// SwiftData-based storage manager for focus sessions
@MainActor
final class SessionStore {
    static let shared = SessionStore()

    private let container: ModelContainer
    private let context: ModelContext

    /// Indicates whether the store is using an in-memory fallback due to persistent storage failure
    private(set) var isUsingInMemoryFallback: Bool = false

    /// The error that occurred during persistent storage initialization, if any
    private(set) var persistentStorageError: Error?

    /// Logger for storage-related events
    private let logger = Logger(subsystem: AppConstants.LoggerSubsystem.main, category: "SessionStore")

    /// UserDefaults key for legacy session data (used for migration)
    private let legacySessionsKey = AppConstants.UserDefaultsKeys.legacySessions
    private let migrationCompletedKey = AppConstants.UserDefaultsKeys.migrationCompleted

    private init() {
        let schema = Schema([FocusSessionModel.self])

        // First, attempt to create a persistent container
        do {
            let persistentConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            container = try ModelContainer(for: schema, configurations: [persistentConfiguration])
            context = ModelContext(container)
            isUsingInMemoryFallback = false
            logger.info("Successfully initialized persistent SwiftData container")
        } catch {
            // Persistent storage failed, fall back to in-memory storage
            persistentStorageError = error
            logger.error("Failed to initialize persistent SwiftData container: \(error.localizedDescription). Falling back to in-memory storage.")

            do {
                let inMemoryConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
                container = try ModelContainer(for: schema, configurations: [inMemoryConfiguration])
                context = ModelContext(container)
                isUsingInMemoryFallback = true
                logger.warning("Using in-memory SwiftData container. Session data will not persist between app launches.")
            } catch {
                // Even in-memory storage failed - this is extremely rare but we still shouldn't crash
                // Create a minimal container as a last resort
                logger.critical("Failed to initialize even in-memory SwiftData container: \(error.localizedDescription)")

                // Last resort: try with default configuration
                do {
                    container = try ModelContainer(for: schema)
                    context = ModelContext(container)
                    isUsingInMemoryFallback = true
                    logger.warning("Using default SwiftData container as last resort fallback.")
                } catch let lastError {
                    // SwiftData is fundamentally broken - create a minimal in-memory container
                    // This should be an extremely rare edge case but we avoid crashing
                    logger.critical("SwiftData is completely unavailable. Unable to create any ModelContainer: \(lastError.localizedDescription)")

                    // Final attempt: create the simplest possible in-memory container
                    // If this fails, we have no choice but to crash as the app cannot function
                    let minimalConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                    // swiftlint:disable:next force_try
                    container = try! ModelContainer(for: schema, configurations: [minimalConfig])
                    context = ModelContext(container)
                    isUsingInMemoryFallback = true
                    persistentStorageError = lastError
                    logger.warning("Created minimal in-memory container after all other attempts failed.")
                }
            }
        }

        // Perform migration from UserDefaults if needed (only for persistent storage)
        if !isUsingInMemoryFallback {
            migrateFromUserDefaultsIfNeeded()
        }
    }

    /// Returns a user-friendly message about the current storage state
    var storageStatusMessage: String? {
        if isUsingInMemoryFallback {
            return "Session data is stored temporarily. Data will be lost when the app closes."
        }
        return nil
    }

    // MARK: - Migration

    /// Migrates legacy session data from UserDefaults to SwiftData
    private func migrateFromUserDefaultsIfNeeded() {
        let userDefaults = UserDefaults.standard

        // Check if migration was already completed
        guard !userDefaults.bool(forKey: migrationCompletedKey) else { return }

        // Attempt to load legacy data
        guard let data = userDefaults.data(forKey: legacySessionsKey),
              let legacySessions = try? JSONDecoder().decode([FocusSession].self, from: data) else {
            // No legacy data to migrate, mark as completed
            userDefaults.set(true, forKey: migrationCompletedKey)
            return
        }

        // Migrate each session
        for session in legacySessions {
            let model = FocusSessionModel(from: session)
            context.insert(model)
        }

        do {
            try context.save()
            // Mark migration as completed
            userDefaults.set(true, forKey: migrationCompletedKey)
            // Optionally remove legacy data after successful migration
            // userDefaults.removeObject(forKey: legacySessionsKey)
            logger.info("Successfully migrated \(legacySessions.count) sessions from UserDefaults")
        } catch {
            logger.error("Failed to migrate sessions from UserDefaults: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - CRUD Operations

    /// Saves a new focus session
    func save(_ session: FocusSession) {
        let model = FocusSessionModel(from: session)
        context.insert(model)

        do {
            try context.save()
        } catch {
            logger.error("Failed to save session: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Saves a new focus session model directly
    func save(_ model: FocusSessionModel) {
        context.insert(model)

        do {
            try context.save()
        } catch {
            logger.error("Failed to save session model: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Fetches all focus sessions, sorted by start time (most recent first)
    func fetchAll() -> [FocusSession] {
        let descriptor = FetchDescriptor<FocusSessionModel>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )

        do {
            let models = try context.fetch(descriptor)
            return models.map { $0.toFocusSession() }
        } catch {
            logger.error("Failed to fetch all sessions: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Fetches all focus session models
    func fetchAllModels() -> [FocusSessionModel] {
        let descriptor = FetchDescriptor<FocusSessionModel>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch all session models: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Fetches sessions from today
    func fetchToday() -> [FocusSession] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()

        return fetchSessionsInRange(from: startOfDay, to: endOfDay)
    }

    /// Fetches sessions from this week
    func fetchThisWeek() -> [FocusSession] {
        let calendar = Calendar.current
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())),
              let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else {
            return []
        }

        return fetchSessionsInRange(from: weekStart, to: weekEnd)
    }

    /// Fetches sessions within a date range
    func fetchSessionsInRange(from startDate: Date, to endDate: Date) -> [FocusSession] {
        let predicate = #Predicate<FocusSessionModel> { session in
            session.startTime >= startDate && session.startTime < endDate
        }

        let descriptor = FetchDescriptor<FocusSessionModel>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )

        do {
            let models = try context.fetch(descriptor)
            return models.map { $0.toFocusSession() }
        } catch {
            logger.error("Failed to fetch sessions in range: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Fetches sessions with a specific label
    func fetchByLabel(_ label: String) -> [FocusSession] {
        let predicate = #Predicate<FocusSessionModel> { session in
            session.label == label
        }

        let descriptor = FetchDescriptor<FocusSessionModel>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )

        do {
            let models = try context.fetch(descriptor)
            return models.map { $0.toFocusSession() }
        } catch {
            logger.error("Failed to fetch sessions by label '\(label, privacy: .private)': \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Deletes a session by ID
    func delete(id: UUID) {
        let predicate = #Predicate<FocusSessionModel> { session in
            session.id == id
        }

        let descriptor = FetchDescriptor<FocusSessionModel>(predicate: predicate)

        do {
            let models = try context.fetch(descriptor)
            for model in models {
                context.delete(model)
            }
            try context.save()
        } catch {
            logger.error("Failed to delete session: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deletes a session
    func delete(_ session: FocusSession) {
        delete(id: session.id)
    }

    /// Deletes all sessions (use with caution)
    func deleteAll() {
        let descriptor = FetchDescriptor<FocusSessionModel>()

        do {
            let models = try context.fetch(descriptor)
            for model in models {
                context.delete(model)
            }
            try context.save()
        } catch {
            logger.error("Failed to delete all sessions: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Returns all unique labels used in sessions
    func fetchAllLabels() -> [String] {
        let sessions = fetchAll()
        let labels = Set(sessions.map { $0.label })
        return Array(labels).sorted()
    }

    /// Returns the total count of sessions
    func count() -> Int {
        let descriptor = FetchDescriptor<FocusSessionModel>()

        do {
            return try context.fetchCount(descriptor)
        } catch {
            logger.error("Failed to count sessions: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }
}
