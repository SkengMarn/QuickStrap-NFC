import Foundation

/// Repository for check-in operations
class CheckinRepository {
    private let networkClient: NetworkClient
    private let logger = AppLogger.shared

    init(networkClient: NetworkClient = .shared) {
        self.networkClient = networkClient
    }

    // MARK: - Check-in Operations

    func recordCheckin(
        wristbandId: String,
        eventId: String,
        staffId: String?,
        location: String?,
        notes: String?,
        gateId: String?,
        appLat: Double?,
        appLon: Double?,
        appAccuracy: Double?
    ) async throws -> CheckinLog {
        logger.info("Recording check-in for wristband: \(wristbandId)", category: "Checkin")

        // Validate required fields
        guard !wristbandId.isEmpty else {
            throw AppError.validationFailed([ValidationFailure("wristbandId", "Wristband ID is required")])
        }
        guard !eventId.isEmpty else {
            throw AppError.validationFailed([ValidationFailure("eventId", "Event ID is required")])
        }

        var checkinData: [String: Any] = [
            "event_id": eventId,
            "wristband_id": wristbandId,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "location": location as Any,
            "notes": notes as Any,
            "ble_seen": [],
            "wifi_ssids": [],
            "probation_tagged": false
        ]

        // Add optional fields only if present and valid
        if let staffId = staffId, !staffId.isEmpty {
            checkinData["staff_id"] = staffId
        }

        if let gateId = gateId, !gateId.isEmpty {
            checkinData["gate_id"] = gateId
        }

        if let lat = appLat, let lon = appLon {
            checkinData["app_lat"] = lat
            checkinData["app_lon"] = lon
            checkinData["app_accuracy"] = appAccuracy as Any
        }

        do {
            let createdLogs: [CheckinLog] = try await networkClient.post(
                endpoint: "rest/v1/checkin_logs",
                body: try JSONSerialization.data(withJSONObject: checkinData),
                headers: ["Prefer": "return=representation"],
                responseType: [CheckinLog].self
            )

            guard let log = createdLogs.first else {
                throw AppError.notFound("Created check-in log")
            }

            logger.info("Check-in recorded successfully: \(log.id)", category: "Checkin")
            return log
        } catch {
            logger.error("Failed to record check-in: \(error.localizedDescription)", category: "Checkin")
            throw error.asAppError()
        }
    }

    func fetchCheckinLogs(for eventId: String, limit: Int = 100) async throws -> [CheckinLog] {
        logger.info("Fetching check-in logs for event: \(eventId)", category: "Checkin")

        do {
            let logs: [CheckinLog] = try await networkClient.get(
                endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&order=timestamp.desc&limit=\(limit)&select=*",
                responseType: [CheckinLog].self
            )

            logger.info("Fetched \(logs.count) check-in logs", category: "Checkin")
            return logs
        } catch {
            logger.error("Failed to fetch check-in logs: \(error.localizedDescription)", category: "Checkin")
            throw error.asAppError()
        }
    }

    func updateCheckinProbationStatus(checkinId: String, probationTagged: Bool) async throws {
        logger.info("Updating probation status for check-in: \(checkinId)", category: "Checkin")

        let updateData: [String: Any] = [
            "probation_tagged": probationTagged
        ]

        do {
            let _: [CheckinLog] = try await networkClient.patch(
                endpoint: "rest/v1/checkin_logs?id=eq.\(checkinId)",
                body: try JSONSerialization.data(withJSONObject: updateData),
                responseType: [CheckinLog].self
            )

            logger.info("Probation status updated successfully", category: "Checkin")
        } catch {
            logger.error("Failed to update probation status: \(error.localizedDescription)", category: "Checkin")
            throw error.asAppError()
        }
    }
}
