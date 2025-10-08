import Foundation
import CoreLocation
import Combine

/// Service responsible for managing gate bindings and discovery
class GateBindingService: ObservableObject {
    static let shared = GateBindingService()
    
    @Published var gateBindings: [GateBinding] = []
    @Published var isProcessing = false
    @Published var currentGate: Gate?
    
    private let supabaseService = SupabaseService.shared
    // private let locationManager = LocationManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupLocationObserver()
    }
    
    private func setupLocationObserver() {
        // locationManager.$currentLocation
        //     .compactMap { $0 }
        //     .sink { [weak self] location in
        //         self?.processLocationUpdate(location)
        //     }
        //     .store(in: &cancellables)
    }
    
    private func processLocationUpdate(_ location: CLLocation) {
        // Process location updates for gate binding
        print("📍 Location update: \(location.coordinate)")
    }
    
    // MARK: - Gate Management
    
    func fetchGates() async throws -> [Gate] {
        guard let eventId = supabaseService.currentEvent?.id else {
            throw AppError.noEventSelected
        }
        
        return try await supabaseService.makeRequest(
            endpoint: "rest/v1/gates?event_id=eq.\(eventId)&select=*",
            method: "GET",
            body: nil,
            responseType: [Gate].self
        )
    }
    
    func discoverGatesFromCheckinPatterns(eventId: String) async throws {
        print("🔍 Discovering gates from check-in patterns...")
        
        // Fetch check-in logs
        let checkins: [CheckinLog] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&select=*",
            method: "GET",
            body: nil,
            responseType: [CheckinLog].self
        )
        
        // Group by location patterns
        let locationGroups = Dictionary(grouping: checkins) { checkin in
            checkin.location ?? "Unknown"
        }
        
        // Create gates for each location group
        for (location, logs) in locationGroups where logs.count >= 5 {
            try await createVirtualGate(
                name: "Virtual Gate - \(location)",
                eventId: eventId,
                checkins: logs
            )
        }
    }
    
    private func createVirtualGate(name: String, eventId: String, checkins: [CheckinLog]) async throws {
        // Calculate average location
        let validCheckins = checkins.compactMap { checkin -> (Double, Double)? in
            guard let lat = checkin.appLat, let lon = checkin.appLon else { return nil }
            return (lat, lon)
        }
        
        guard !validCheckins.isEmpty else { return }
        
        let avgLat = validCheckins.map { $0.0 }.reduce(0, +) / Double(validCheckins.count)
        let avgLon = validCheckins.map { $0.1 }.reduce(0, +) / Double(validCheckins.count)
        
        let gate = Gate(
            id: UUID().uuidString,
            eventId: eventId,
            name: name,
            latitude: avgLat,
            longitude: avgLon
        )
        
        let _: [Gate] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/gates",
            method: "POST",
            body: try JSONEncoder().encode(gate),
            responseType: [Gate].self
        )
        
        print("✅ Created virtual gate: \(name)")
    }
    
    // MARK: - Additional Methods for GateProcessingService
    
    func fetchActiveGatesWithScans(for eventId: String) async throws -> [Gate] {
        // Fetch gates for the event
        let gates: [Gate] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/gates?event_id=eq.\(eventId)&select=*",
            method: "GET",
            body: nil,
            responseType: [Gate].self
        )
        
        return gates
    }
    
    func fetchAllGateBindings() async throws -> [GateBinding] {
        guard let eventId = supabaseService.currentEvent?.id else {
            throw AppError.noEventSelected
        }
        
        let bindings: [GateBinding] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/gate_bindings?event_id=eq.\(eventId)&select=*",
            method: "GET",
            body: nil,
            responseType: [GateBinding].self
        )
        
        return bindings
    }
    
    func getScanCountForGate(_ gateId: String, eventId: String) async throws -> Int {
        let checkins: [CheckinLog] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&gate_id=eq.\(gateId)&select=id",
            method: "GET",
            body: nil,
            responseType: [CheckinLog].self
        )
        
        return checkins.count
    }
    
    func evaluateCheckin(wristbandId: String, categoryName: String, gateId: String) async throws -> CheckinPolicyResult {
        // Simple policy evaluation - can be enhanced later
        return CheckinPolicyResult(
            allowed: true,
            reason: .okEnforced,
            locationConfidence: 1.0,
            warnings: []
        )
    }
    
    func detectNearbyGates(eventId: String) async throws {
        // Simple implementation - just fetch gates for the event
        let gates = try await fetchActiveGatesWithScans(for: eventId)
        await MainActor.run {
            self.currentGate = gates.first
        }
    }
}

// MARK: - Location Manager Extension (Commented out)

// extension GateBindingService: CLLocationManagerDelegate {
//     func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//         guard let location = locations.last else { return }
//         processLocationUpdate(location)
//     }
//     
//     func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
//         let isAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
//         let wasAuthorized = locationManager.authorizationStatus == .authorizedWhenInUse || 
//                            locationManager.authorizationStatus == .authorizedAlways
//         
//         if isAuthorized && !wasAuthorized {
//             print("📍 Starting location updates...")
//             locationManager.startUpdatingLocation()
//         }
//     }
//     
//     func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
//         print("📍 Location error: \(error.localizedDescription)")
//     }
// }
