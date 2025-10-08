import Foundation

// MARK: - Enhanced Database Models for Supabase RPC Functions

/// Event category with wristband count
struct EventCategory: Codable, Identifiable {
    let id = UUID()
    let name: String
    let wristbandCount: Int
    
    var displayName: String {
        return name.isEmpty ? "General" : name
    }
    
    var color: String {
        // Provide colors based on common category patterns
        switch name.lowercased() {
        case let n where n.contains("vip"):
            return "#FFD700" // Gold
        case let n where n.contains("general"):
            return "#0056D2" // Blue
        case let n where n.contains("staff"):
            return "#00C853" // Green
        case let n where n.contains("press") || n.contains("media"):
            return "#757575" // Gray
        case let n where n.contains("artist") || n.contains("performer"):
            return "#E91E63" // Pink
        case let n where n.contains("crew") || n.contains("vendor"):
            return "#FF9800" // Orange
        case let n where n.contains("early"):
            return "#8BC34A" // Light Green
        default:
            return "#9E9E9E" // Default Grey
        }
    }
}

/// Result from processing unlinked check-ins
struct ProcessingResult: Codable {
    let processedCount: Int
    let linkedCount: Int
    let successRate: Double
    
    var efficiency: ProcessingEfficiency {
        switch successRate {
        case 0.9...1.0: return .excellent
        case 0.7..<0.9: return .good
        case 0.5..<0.7: return .fair
        default: return .poor
        }
    }
}

enum ProcessingEfficiency: String, CaseIterable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    
    var color: String {
        switch self {
        case .excellent: return "#4CAF50" // Green
        case .good: return "#8BC34A" // Light Green
        case .fair: return "#FF9800" // Orange
        case .poor: return "#F44336" // Red
        }
    }
    
    var icon: String {
        switch self {
        case .excellent: return "checkmark.circle.fill"
        case .good: return "checkmark.circle"
        case .fair: return "exclamationmark.triangle"
        case .poor: return "xmark.circle"
        }
    }
}

/// Comprehensive event statistics from enhanced RPC
struct ComprehensiveEventStats: Codable {
    let totalWristbands: Int
    let totalCheckins: Int
    let uniqueCheckins: Int
    let linkedCheckins: Int
    let unlinkedCheckins: Int
    let totalGates: Int
    let activeGates: Int
    let categoriesCount: Int
    let avgCheckinsPerGate: Double
    let linkingRate: Double
    
    // Computed properties for UI display
    var checkInRate: Double {
        totalWristbands > 0 ? Double(uniqueCheckins) / Double(totalWristbands) : 0.0
    }
    
    var gateUtilization: Double {
        totalGates > 0 ? Double(activeGates) / Double(totalGates) : 0.0
    }
    
    var linkingQuality: LinkingQuality {
        switch linkingRate {
        case 0.9...1.0: return .excellent
        case 0.7..<0.9: return .good
        case 0.5..<0.7: return .fair
        default: return .poor
        }
    }
    
    var averageScansPerWristband: Double {
        uniqueCheckins > 0 ? Double(totalCheckins) / Double(uniqueCheckins) : 0.0
    }
}

enum LinkingQuality: String, CaseIterable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    
    var color: String {
        switch self {
        case .excellent: return "#4CAF50"
        case .good: return "#8BC34A"
        case .fair: return "#FF9800"
        case .poor: return "#F44336"
        }
    }
    
    var description: String {
        switch self {
        case .excellent: return "90%+ check-ins linked to gates"
        case .good: return "70-89% check-ins linked to gates"
        case .fair: return "50-69% check-ins linked to gates"
        case .poor: return "Less than 50% check-ins linked"
        }
    }
}

/// Nearby gate information from proximity search
struct NearbyGate: Codable, Identifiable {
    let id = UUID()
    let gateId: String
    let gateName: String
    let distanceMeters: Double
    
    var formattedDistance: String {
        if distanceMeters < 1000 {
            return String(format: "%.0fm", distanceMeters)
        } else {
            return String(format: "%.1fkm", distanceMeters / 1000)
        }
    }
    
    var proximityLevel: ProximityLevel {
        switch distanceMeters {
        case 0..<10: return .immediate
        case 10..<25: return .close
        case 25..<50: return .nearby
        case 50..<100: return .distant
        default: return .faraway
        }
    }
}

enum ProximityLevel: String, CaseIterable {
    case immediate = "Immediate"
    case close = "Close"
    case nearby = "Nearby"
    case distant = "Distant"
    case faraway = "Far Away"
    
    var color: String {
        switch self {
        case .immediate: return "#4CAF50"
        case .close: return "#8BC34A"
        case .nearby: return "#FFC107"
        case .distant: return "#FF9800"
        case .faraway: return "#F44336"
        }
    }
    
    var icon: String {
        switch self {
        case .immediate: return "location.fill"
        case .close: return "location"
        case .nearby: return "location.circle"
        case .distant: return "location.circle.fill"
        case .faraway: return "questionmark.circle"
        }
    }
}

// MARK: - Enhanced Check-in Models

/// Check-in with category information from database view
struct CheckinWithCategory: Codable, Identifiable {
    let id: String
    let eventId: String
    let wristbandId: String
    let staffId: String?
    let timestamp: Date
    let location: String?
    let notes: String?
    let gateId: String?
    let scannerId: String?
    let appLat: Double?
    let appLon: Double?
    let appAccuracy: Double?
    let bleSeen: [String]?
    let wifiSSIDs: [String]?
    let probationTagged: Bool?
    
    // Enhanced fields from view
    let wristbandCategory: String?
    let nfcId: String?
    let gateName: String?
    let gateStatus: String?
    let gateConfidence: Double?
    
    enum CodingKeys: String, CodingKey {
        case id, timestamp, location, notes
        case eventId = "event_id"
        case wristbandId = "wristband_id"
        case staffId = "staff_id"
        case gateId = "gate_id"
        case scannerId = "scanner_id"
        case appLat = "app_lat"
        case appLon = "app_lon"
        case appAccuracy = "app_accuracy"
        case bleSeen = "ble_seen"
        case wifiSSIDs = "wifi_ssids"
        case probationTagged = "probation_tagged"
        case wristbandCategory = "wristband_category"
        case nfcId = "nfc_id"
        case gateName = "gate_name"
        case gateStatus = "gate_status"
        case gateConfidence = "gate_confidence"
    }
    
    var hasGPSData: Bool {
        appLat != nil && appLon != nil
    }
    
    var isLinkedToGate: Bool {
        gateId != nil
    }
    
    var categoryDisplayName: String {
        wristbandCategory?.isEmpty == false ? wristbandCategory! : "General"
    }
    
    var gateStatusDisplayName: String {
        switch gateStatus?.lowercased() {
        case "enforced": return "Enforced"
        case "probation": return "Learning"
        case "unbound": return "Unbound"
        default: return "Unknown"
        }
    }
}

// MARK: - Analytics Models

/// Category statistics for event dashboard
struct CategoryAnalytics: Codable, Identifiable {
    let id = UUID()
    let eventId: String
    let eventName: String
    let category: String
    let totalWristbands: Int
    let totalCheckins: Int
    let uniqueGatesUsed: Int
    
    var checkInRate: Double {
        totalWristbands > 0 ? Double(totalCheckins) / Double(totalWristbands) : 0.0
    }
    
    var averageCheckinsPerWristband: Double {
        totalWristbands > 0 ? Double(totalCheckins) / Double(totalWristbands) : 0.0
    }
    
    var gateSpread: GateSpread {
        switch uniqueGatesUsed {
        case 0: return .none
        case 1: return .single
        case 2...3: return .limited
        case 4...6: return .moderate
        default: return .wide
        }
    }
}

enum GateSpread: String, CaseIterable {
    case none = "No Gates"
    case single = "Single Gate"
    case limited = "Limited"
    case moderate = "Moderate"
    case wide = "Wide Spread"
    
    var description: String {
        switch self {
        case .none: return "No gate usage recorded"
        case .single: return "All activity through one gate"
        case .limited: return "2-3 gates used"
        case .moderate: return "4-6 gates used"
        case .wide: return "7+ gates used"
        }
    }
    
    var color: String {
        switch self {
        case .none: return "#9E9E9E"
        case .single: return "#F44336"
        case .limited: return "#FF9800"
        case .moderate: return "#8BC34A"
        case .wide: return "#4CAF50"
        }
    }
}

// MARK: - Unlinked Check-ins Model

/// Unlinked check-in with category for processing
struct UnlinkedCheckin: Codable, Identifiable {
    let id: String
    let eventId: String
    let wristbandId: String
    let category: String
    let appLat: Double?
    let appLon: Double?
    let appAccuracy: Double?
    let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case id, category, timestamp
        case eventId = "event_id"
        case wristbandId = "wristband_id"
        case appLat = "app_lat"
        case appLon = "app_lon"
        case appAccuracy = "app_accuracy"
    }
    
    var hasGPSData: Bool {
        appLat != nil && appLon != nil
    }
    
    var gpsQuality: GPSQuality {
        guard let accuracy = appAccuracy else { return .unknown }
        
        switch accuracy {
        case 0..<5: return .excellent
        case 5..<15: return .good
        case 15..<30: return .fair
        case 30..<100: return .poor
        default: return .unusable
        }
    }
}

enum GPSQuality: String, CaseIterable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    case unusable = "Unusable"
    case unknown = "Unknown"
    
    var color: String {
        switch self {
        case .excellent: return "#4CAF50"
        case .good: return "#8BC34A"
        case .fair: return "#FFC107"
        case .poor: return "#FF9800"
        case .unusable: return "#F44336"
        case .unknown: return "#9E9E9E"
        }
    }
    
    var description: String {
        switch self {
        case .excellent: return "< 5m accuracy"
        case .good: return "5-15m accuracy"
        case .fair: return "15-30m accuracy"
        case .poor: return "30-100m accuracy"
        case .unusable: return "> 100m accuracy"
        case .unknown: return "No GPS data"
        }
    }
}
