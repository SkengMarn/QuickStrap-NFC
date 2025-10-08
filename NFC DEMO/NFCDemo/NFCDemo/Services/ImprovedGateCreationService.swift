import Foundation
import CoreLocation

/// Improved gate creation service with stricter duplicate prevention
class ImprovedGateCreationService {
    static let shared = ImprovedGateCreationService()
    private let supabaseService = SupabaseService.shared

    // MARK: - Stricter Thresholds

    struct StrictThresholds {
        // INCREASED from 10 → 20 (need more evidence before creating gate)
        static let minScansForGateCreation = 20

        // INCREASED from 10 → 15 (need more evidence for cluster)
        static let minScansForLocationCluster = 15

        // INCREASED from 25m → 50m (more aggressive duplicate detection)
        static let deduplicationRadius = 50.0

        // NEW: Minimum time window before creating gate
        static let minTimeWindowHours = 1.0

        // NEW: Maximum gates per event (safety limit)
        static let maxGatesPerEvent = 20

        // NEW: Require manual approval for gate creation
        static let requireManualApproval = false // Set to true for production
    }

    // MARK: - Improved Name Normalization

    /// Normalize gate names to prevent duplicates with slight variations
    func normalizeGateName(_ name: String) -> String {
        let lowercased = name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove ALL variations of "gate", "entrance", "area", "door"
        let variations = [
            "virtual gate", "gate", "entrance", "area", "door", "exit",
            "check-in", "checkin", "manual", "-", "the"
        ]

        var normalized = lowercased
        for variation in variations {
            normalized = normalized.replacingOccurrences(of: variation, with: "")
        }

        // Trim extra spaces
        normalized = normalized.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Canonical names (prevent "vip", "v.i.p", "vip lounge" from being different)
        if normalized.contains("vip") || normalized.contains("v.i.p") {
            return "vip"
        } else if normalized.contains("staff") || normalized.contains("crew") {
            return "staff"
        } else if normalized.contains("general") || normalized.contains("ga") || normalized.contains("main") {
            return "general"
        } else if normalized.contains("artist") || normalized.contains("performer") || normalized.contains("talent") {
            return "artist"
        } else if normalized.contains("vendor") || normalized.contains("catering") || normalized.contains("food") {
            return "vendor"
        } else if normalized.contains("press") || normalized.contains("media") {
            return "press"
        }

        return normalized.isEmpty ? "general" : normalized
    }

    // MARK: - Global Duplicate Check

    /// Check if gate already exists globally (not just in cluster)
    func findExistingGate(
        normalizedName: String,
        location: CLLocationCoordinate2D,
        eventId: String,
        existingGates: [Gate]
    ) -> Gate? {

        for gate in existingGates {
            // Check 1: Name similarity
            let existingNormalized = normalizeGateName(gate.name)

            guard existingNormalized == normalizedName else {
                continue // Different name, skip
            }

            // Check 2: Location proximity
            guard let gateLat = gate.latitude, let gateLon = gate.longitude else {
                continue // No GPS, skip
            }

            let distance = LocationMathService.haversineDistance(
                lat1: location.latitude, lon1: location.longitude,
                lat2: gateLat, lon2: gateLon
            )

            if distance <= StrictThresholds.deduplicationRadius {
                print("🎯 Found existing gate: \(gate.name) (\(Int(distance))m away)")
                return gate
            }
        }

        return nil
    }

    // MARK: - Smart Gate Consolidation

    /// Instead of creating multiple gates, create ONE gate per category with multiple bindings
    func createConsolidatedGates(
        from checkinLogs: [CheckinLog],
        eventId: String
    ) async throws -> [Gate] {

        print("🔍 Analyzing \(checkinLogs.count) check-ins for consolidated gate creation...")

        // Step 1: Get existing gates
        let existingGates = try await fetchGates(for: eventId)

        // Step 2: Safety check - prevent gate spam
        if existingGates.count >= StrictThresholds.maxGatesPerEvent {
            print("⚠️ Maximum gates reached (\(existingGates.count)/\(StrictThresholds.maxGatesPerEvent))")
            print("💡 Consider deduplication or manual gate management")
            return []
        }

        // Step 3: Group by NORMALIZED location
        var locationGroups: [String: [CheckinLog]] = [:]

        for log in checkinLogs {
            let normalizedLocation = normalizeLocationString(log.location ?? "unknown")
            locationGroups[normalizedLocation, default: []].append(log)
        }

        print("📍 Found \(locationGroups.count) unique normalized locations")

        var createdGates: [Gate] = []

        // Step 4: For each location group, create SINGLE gate with multiple bindings
        for (normalizedLocation, logs) in locationGroups {
            // Must meet minimum threshold
            guard logs.count >= StrictThresholds.minScansForLocationCluster else {
                print("⏭️ Skipping \(normalizedLocation): only \(logs.count) scans (need \(StrictThresholds.minScansForLocationCluster))")
                continue
            }

            // Calculate average GPS
            let coordinates = logs.compactMap { log -> CLLocationCoordinate2D? in
                guard let lat = log.appLat, let lon = log.appLon else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }

            guard !coordinates.isEmpty else {
                print("⏭️ Skipping \(normalizedLocation): no GPS data")
                continue
            }

            let avgLat = coordinates.map { $0.latitude }.reduce(0, +) / Double(coordinates.count)
            let avgLon = coordinates.map { $0.longitude }.reduce(0, +) / Double(coordinates.count)
            let avgLocation = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)

            // Check if gate already exists
            if let existingGate = findExistingGate(
                normalizedName: normalizedLocation,
                location: avgLocation,
                eventId: eventId,
                existingGates: existingGates + createdGates
            ) {
                print("🔄 Gate already exists: \(existingGate.name) - skipping creation")
                continue
            }

            // Extract categories
            let categoryGroups = Dictionary(grouping: logs) { log in
                extractCategory(from: log.wristbandId)
            }

            // Generate smart gate name (use dominant category)
            let dominantCategory = categoryGroups.max { $0.value.count < $1.value.count }?.key ?? "General"
            let gateName = generateCanonicalGateName(
                normalizedLocation: normalizedLocation,
                dominantCategory: dominantCategory
            )

            // Create single gate
            print("🏗️ Creating gate: \(gateName) with \(categoryGroups.count) categories")

            let gateData: [String: Any] = [
                "event_id": eventId,
                "name": gateName,
                "latitude": avgLat,
                "longitude": avgLon
            ]

            let createdGatesResponse: [Gate] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/gates",
                method: "POST",
                body: try JSONSerialization.data(withJSONObject: gateData),
                responseType: [Gate].self
            )

            guard let newGate = createdGatesResponse.first else {
                print("❌ Failed to create gate for \(normalizedLocation)")
                continue
            }

            // Create bindings for ALL categories at this gate
            for (category, categoryLogs) in categoryGroups {
                if categoryLogs.count >= 5 { // Minimum 5 scans for binding
                    try await createBinding(
                        gateId: newGate.id,
                        category: category,
                        sampleCount: categoryLogs.count,
                        eventId: eventId
                    )
                }
            }

            createdGates.append(newGate)
            print("✅ Created gate: \(gateName) with \(categoryGroups.count) category bindings")
        }

        print("🎉 Gate creation complete: \(createdGates.count) gates created")
        return createdGates
    }

    // MARK: - Canonical Name Generation

    /// Generate consistent gate names to prevent variations
    private func generateCanonicalGateName(
        normalizedLocation: String,
        dominantCategory: String
    ) -> String {

        // Use canonical names only (prevent "VIP Gate" vs "VIP Entrance" duplicates)
        switch normalizedLocation {
        case "vip":
            return "VIP Gate"
        case "staff":
            return "Staff Gate"
        case "general", "main":
            return "Main Gate"
        case "artist":
            return "Artist Gate"
        case "vendor":
            return "Vendor Gate"
        case "press":
            return "Press Gate"
        default:
            // If unknown, use category
            return "\(dominantCategory) Gate"
        }
    }

    // MARK: - Helper Methods

    private func normalizeLocationString(_ location: String) -> String {
        let lowercased = location.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove common prefixes
        var normalized = lowercased
            .replacingOccurrences(of: "manual check-in - ", with: "")
            .replacingOccurrences(of: "manual checkin - ", with: "")
            .replacingOccurrences(of: "check-in - ", with: "")
            .replacingOccurrences(of: "checkin - ", with: "")

        // Canonical mapping
        if normalized.contains("vip") { return "vip" }
        if normalized.contains("staff") || normalized.contains("crew") { return "staff" }
        if normalized.contains("general") || normalized.contains("main") { return "general" }
        if normalized.contains("artist") || normalized.contains("performer") { return "artist" }
        if normalized.contains("vendor") || normalized.contains("catering") { return "vendor" }
        if normalized.contains("press") || normalized.contains("media") { return "press" }

        return normalized
    }

    private func extractCategory(from wristbandId: String) -> String {
        let wristbandLower = wristbandId.lowercased()

        if wristbandLower.hasPrefix("vip") || wristbandLower.contains("vip") {
            return "VIP"
        } else if wristbandLower.hasPrefix("staff") || wristbandLower.contains("staff") {
            return "Staff"
        } else if wristbandLower.hasPrefix("artist") || wristbandLower.contains("artist") {
            return "Artist"
        } else if wristbandLower.hasPrefix("vendor") || wristbandLower.contains("vendor") {
            return "Vendor"
        } else if wristbandLower.hasPrefix("press") || wristbandLower.contains("press") {
            return "Press"
        } else {
            return "General"
        }
    }

    private func createBinding(
        gateId: String,
        category: String,
        sampleCount: Int,
        eventId: String
    ) async throws {

        let confidence = LocationMathService.wilsonLowerBound(k: sampleCount, n: sampleCount + 10)
        let status: String = (confidence >= 0.75 && sampleCount >= 12) ? "enforced" : "probation"

        let bindingData: [String: Any] = [
            "gate_id": gateId,
            "category": category,
            "status": status,
            "confidence": confidence,
            "sample_count": sampleCount,
            "event_id": eventId
        ]

        do {
            let _: [GateBinding] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/gate_bindings",
                method: "POST",
                body: try JSONSerialization.data(withJSONObject: bindingData),
                responseType: [GateBinding].self
            )

            print("  ✅ Binding: \(category) → \(gateId) (\(status), \(Int(confidence * 100))%)")
        } catch {
            print("  ⚠️ Failed to create binding for \(category): \(error)")
        }
    }

    private func fetchGates(for eventId: String) async throws -> [Gate] {
        return try await supabaseService.makeRequest(
            endpoint: "rest/v1/gates?event_id=eq.\(eventId)&select=*",
            method: "GET",
            body: nil,
            responseType: [Gate].self
        )
    }
}
