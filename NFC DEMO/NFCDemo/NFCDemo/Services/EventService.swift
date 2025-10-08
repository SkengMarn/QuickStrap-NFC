import Foundation
import Combine

/// Focused event management service
class EventService: ObservableObject {
    static let shared = EventService()

    private let repository: EventRepository
    private let logger = AppLogger.shared

    @Published var currentEvent: Event?
    @Published var events: [Event] = []
    @Published var isLoading = false

    private init(repository: EventRepository = EventRepository()) {
        self.repository = repository
        logger.info("EventService initialized", category: "Events")
    }

    // MARK: - Event Operations

    @MainActor
    func fetchEvents() async throws -> [Event] {
        logger.info("Fetching events", category: "Events")
        isLoading = true
        defer { isLoading = false }

        do {
            let fetchedEvents = try await repository.fetchEvents()
            events = fetchedEvents
            return fetchedEvents
        } catch {
            logger.error("Failed to fetch events: \(error.localizedDescription)", category: "Events")
            throw error.asAppError()
        }
    }

    @MainActor
    func selectEvent(_ event: Event) {
        logger.info("Selecting event: \(event.name)", category: "Events")
        currentEvent = event
    }

    @MainActor
    func clearSelection() {
        logger.info("Clearing event selection", category: "Events")
        currentEvent = nil
    }
}
