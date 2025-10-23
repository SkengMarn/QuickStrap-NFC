import Foundation

/// Repository for wristband operations
class WristbandRepository {
    private let networkClient: NetworkClient
    private let logger = AppLogger.shared

    init(networkClient: NetworkClient = .shared) {
        self.networkClient = networkClient
    }

    // MARK: - Wristband Operations

    func fetchWristbands(for eventId: String) async throws -> [Wristband] {
        logger.info("Fetching wristbands for parent event: \(eventId) (series_id IS NULL)", category: "Wristbands")

        do {
            // Filter by series_id IS NULL to only get parent event wristbands
            let wristbands: [Wristband] = try await networkClient.get(
                endpoint: "rest/v1/wristbands?event_id=eq.\(eventId)&is_active=eq.true&series_id=is.null&select=*",
                responseType: [Wristband].self
            )

            logger.info("Fetched \(wristbands.count) parent event wristbands (excluding series)", category: "Wristbands")
            return wristbands
        } catch {
            logger.error("Failed to fetch wristbands: \(error.localizedDescription)", category: "Wristbands")
            throw error.asAppError()
        }
    }

    func fetchWristband(by nfcId: String, eventId: String) async throws -> Wristband? {
        logger.info("Fetching wristband with NFC ID: \(nfcId)", category: "Wristbands")

        do {
            let wristbands: [Wristband] = try await networkClient.get(
                endpoint: "rest/v1/wristbands?nfc_id=eq.\(nfcId)&event_id=eq.\(eventId)&is_active=eq.true&select=*",
                responseType: [Wristband].self
            )

            logger.info("Wristband fetch successful", category: "Wristbands")
            return wristbands.first
        } catch {
            logger.error("Failed to fetch wristband: \(error.localizedDescription)", category: "Wristbands")
            throw error.asAppError()
        }
    }

    func fetchWristbandById(_ id: String, eventId: String) async throws -> Wristband? {
        logger.info("Fetching wristband: \(id)", category: "Wristbands")

        do {
            let wristbands: [Wristband] = try await networkClient.get(
                endpoint: "rest/v1/wristbands?id=eq.\(id)&event_id=eq.\(eventId)&select=*",
                responseType: [Wristband].self
            )

            return wristbands.first
        } catch {
            logger.error("Failed to fetch wristband \(id): \(error.localizedDescription)", category: "Wristbands")
            throw error.asAppError()
        }
    }

    func createWristband(_ wristband: Wristband) async throws -> Wristband {
        logger.info("Creating wristband with NFC ID: \(wristband.nfcId)", category: "Wristbands")

        let wristbandData: [String: Any] = [
            "event_id": wristband.eventId,
            "nfc_id": wristband.nfcId,
            "category": wristband.category.name,
            "is_active": wristband.isActive
        ]

        do {
            let createdWristbands: [Wristband] = try await networkClient.post(
                endpoint: "rest/v1/wristbands",
                body: try JSONSerialization.data(withJSONObject: wristbandData),
                headers: ["Prefer": "return=representation"],
                responseType: [Wristband].self
            )

            guard let created = createdWristbands.first else {
                throw AppError.notFound("Created wristband")
            }

            logger.info("Wristband created successfully: \(created.id)", category: "Wristbands")
            return created
        } catch {
            logger.error("Failed to create wristband: \(error.localizedDescription)", category: "Wristbands")
            throw error.asAppError()
        }
    }

    func fetchCategories(for eventId: String) async throws -> [WristbandCategory] {
        logger.info("Fetching categories for event: \(eventId)", category: "Wristbands")

        do {
            let response: [[String: String]] = try await networkClient.get(
                endpoint: "rest/v1/wristbands?event_id=eq.\(eventId)&select=category",
                responseType: [[String: String]].self
            )

            let categoryNames = Set(response.compactMap { $0["category"] })
            let categories = categoryNames.map { WristbandCategory(name: $0) }.sorted { $0.name < $1.name }

            logger.info("Found \(categories.count) categories", category: "Wristbands")
            return categories
        } catch {
            logger.error("Failed to fetch categories: \(error.localizedDescription)", category: "Wristbands")
            throw error.asAppError()
        }
    }

    func searchWristbands(eventId: String, searchText: String, category: WristbandCategory?, status: WristbandStatusFilter) async throws -> [Wristband] {
        // For now, fetch all and filter client-side
        // TODO: Implement server-side filtering with proper query params
        let allWristbands = try await fetchWristbands(for: eventId)

        return allWristbands.filter { wristband in
            let matchesSearch = searchText.isEmpty ||
                wristband.nfcId.localizedCaseInsensitiveContains(searchText) ||
                wristband.category.displayName.localizedCaseInsensitiveContains(searchText)

            let matchesCategory = category == nil || wristband.category == category

            let matchesStatus = status == .all ||
                (status == .checkedIn && wristband.isCheckedIn) ||
                (status == .pending && !wristband.isCheckedIn)

            return matchesSearch && matchesCategory && matchesStatus
        }
    }
}
