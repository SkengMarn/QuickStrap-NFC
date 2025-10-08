import Foundation

// MARK: - Supporting Models

struct CategoryStat: Identifiable {
    let id = UUID()
    let category: String
    let count: Int
}

struct TimelinePoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let count: Int
}

struct GateStats {
    let status: GateBindingStatus
    let confidence: Double
    let totalScans: Int
    let lastHourScans: Int
    let avgPerHour: Int
    let peakHour: Int
    let categories: [String]
}

struct GateDetailStats {
    let totalScans: Int
    let lastHourScans: Int
    let avgPerHour: Int
    let peakHour: Int
}

// GateBindingStatus and GateBinding are already defined in GateModels.swift

enum HealthStatus {
    case good, warning, attention
}

enum TimeRange {
    case lastHour
    case last24Hours
    case thisEvent
    case all
}
