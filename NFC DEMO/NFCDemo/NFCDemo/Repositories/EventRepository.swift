import Foundation

/// Repository for event operations
class EventRepository {
    private let networkClient: NetworkClient
    private let logger = AppLogger.shared

    init(networkClient: NetworkClient = .shared) {
        self.networkClient = networkClient
    }

    // MARK: - Event Operations

    func fetchEvents() async throws -> [Event] {
        logger.info("Fetching events from database", category: "Events")

        do {
            let events: [Event] = try await networkClient.get(
                endpoint: "rest/v1/events?select=*",
                responseType: [Event].self
            )

            logger.info("Fetched \(events.count) events", category: "Events")
            return events
        } catch {
            logger.error("Failed to fetch events: \(error.localizedDescription)", category: "Events")
            throw error.asAppError()
        }
    }

    func fetchEvent(id: String) async throws -> Event? {
        logger.info("Fetching event: \(id)", category: "Events")

        do {
            let events: [Event] = try await networkClient.get(
                endpoint: "rest/v1/events?id=eq.\(id)&select=*",
                responseType: [Event].self
            )

            logger.info("Event fetch successful", category: "Events")
            return events.first
        } catch {
            logger.error("Failed to fetch event \(id): \(error.localizedDescription)", category: "Events")
            throw error.asAppError()
        }
    }

    func createEvent(_ event: Event) async throws -> Event {
        logger.info("Creating event: \(event.name)", category: "Events")

        let eventData: [String: Any] = [
            "name": event.name,
            "description": event.description as Any,
            "location": event.location as Any,
            "start_date": ISO8601DateFormatter().string(from: event.startDate),
            "end_date": event.endDate.map { ISO8601DateFormatter().string(from: $0) } as Any,
            "total_capacity": event.totalCapacity as Any
        ]

        do {
            let createdEvents: [Event] = try await networkClient.post(
                endpoint: "rest/v1/events",
                body: try JSONSerialization.data(withJSONObject: eventData),
                headers: ["Prefer": "return=representation"],
                responseType: [Event].self
            )

            guard let createdEvent = createdEvents.first else {
                throw AppError.notFound("Created event")
            }

            logger.info("Event created successfully: \(createdEvent.id)", category: "Events")
            return createdEvent
        } catch {
            logger.error("Failed to create event: \(error.localizedDescription)", category: "Events")
            throw error.asAppError()
        }
    }
}
