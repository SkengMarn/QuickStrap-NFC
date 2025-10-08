// Compilation Test File
// This file tests that all the main components compile correctly

import SwiftUI
import Foundation
import CoreLocation

// Test that all the main services can be instantiated
func testServicesCompilation() {
    let _ = GateDeduplicationService.shared
    let _ = GateBindingService.shared
    let _ = SupabaseService.shared
}

// Test that all the main views can be instantiated
func testViewsCompilation() {
    let _ = GateDeduplicationView()
    let _ = EnhancedStatsView()
}

// Test that all the main models can be created
func testModelsCompilation() {
    let gate = Gate(
        id: "test",
        eventId: "test-event",
        name: "Test Gate",
        latitude: 0.0,
        longitude: 0.0,
        createdAt: Date(),
        updatedAt: Date()
    )
    
    let category = WristbandCategory(name: "Test")
    
    let binding = GateBinding(
        gateId: "test-gate",
        categoryName: "Test",
        status: .probation,
        confidence: 0.5,
        sampleCount: 10,
        eventId: "test-event",
        boundAt: Date()
    )
    
    print("✅ All models compile correctly")
    print("Gate: \(gate.name)")
    print("Category: \(category.name)")
    print("Binding: \(binding.status.rawValue)")
}

// Test threshold verification
func testThresholdVerification() {
    let service = GateDeduplicationService.shared
    
    let mockGate = Gate(
        id: "test-gate",
        eventId: "test-event",
        name: "Test Gate",
        latitude: 0.0,
        longitude: 0.0,
        createdAt: Date(),
        updatedAt: Date()
    )
    
    let mockCluster = GateCluster(
        primaryGate: mockGate,
        duplicateGates: [],
        mergedBindings: [],
        averageLocation: CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),
        totalSampleCount: 60,
        highestConfidence: 0.65
    )
    
    let result = service.verifyPostDeduplicationThresholds(cluster: mockCluster)
    print("✅ Threshold verification works")
    print("Qualifies for binding: \(result.qualifiesForBinding)")
    print("Recommended status: \(result.recommendedStatus)")
}

print("🧪 Running compilation tests...")
testServicesCompilation()
testViewsCompilation()
testModelsCompilation()
testThresholdVerification()
print("✅ All compilation tests passed!")
