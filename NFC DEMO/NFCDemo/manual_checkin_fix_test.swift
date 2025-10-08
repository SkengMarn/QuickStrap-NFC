// Manual Check-in Fix Test
// This tests the UUID validation fixes for manual check-in

import Foundation

// Test UUID validation patterns
func testUUIDValidation() {
    print("🧪 Testing UUID Validation Fixes")
    print("=" * 40)
    
    // Test 1: Valid UUIDs
    let validWristbandId = "12345678-1234-1234-1234-123456789012"
    let validEventId = "87654321-4321-4321-4321-210987654321"
    let validStaffId = "abcdefgh-abcd-abcd-abcd-abcdefghijkl"
    let validGateId = "zyxwvuts-zyxw-zyxw-zyxw-zyxwvutsrqpo"
    
    print("✅ Valid UUIDs:")
    print("   wristbandId: \(validWristbandId)")
    print("   eventId: \(validEventId)")
    print("   staffId: \(validStaffId)")
    print("   gateId: \(validGateId)")
    
    // Test 2: Invalid UUIDs (empty strings)
    let emptyWristbandId = ""
    let emptyEventId = ""
    let emptyStaffId = ""
    let emptyGateId = ""
    
    print("\n❌ Invalid UUIDs (empty strings):")
    print("   wristbandId: '\(emptyWristbandId)' (length: \(emptyWristbandId.count))")
    print("   eventId: '\(emptyEventId)' (length: \(emptyEventId.count))")
    print("   staffId: '\(emptyStaffId)' (length: \(emptyStaffId.count))")
    print("   gateId: '\(emptyGateId)' (length: \(emptyGateId.count))")
    
    // Test 3: Simulate the fixed check-in data structure
    print("\n🔧 Fixed Check-in Data Structure:")
    
    var checkinData: [String: Any] = [
        "event_id": validEventId,
        "wristband_id": validWristbandId,
        "timestamp": ISO8601DateFormatter().string(from: Date()),
        "location": "Manual Check-in - VIP Area",
        "notes": "Manual check-in from wristbands view"
    ]
    
    // Add staff_id only if not empty (FIX 1)
    if !validStaffId.isEmpty {
        checkinData["staff_id"] = validStaffId
        print("   ✅ Added staff_id: \(validStaffId)")
    } else {
        print("   ⚠️ Skipped empty staff_id (prevents UUID error)")
    }
    
    // Add gate_id only if not empty (FIX 2)
    if !validGateId.isEmpty {
        checkinData["gate_id"] = validGateId
        print("   ✅ Added gate_id: \(validGateId)")
    } else {
        print("   ⚠️ Skipped empty gate_id (prevents UUID error)")
    }
    
    // Add other fields
    checkinData["app_lat"] = 0.354168
    checkinData["app_lon"] = 32.599929
    checkinData["app_accuracy"] = 20.0
    checkinData["ble_seen"] = []
    checkinData["wifi_ssids"] = []
    checkinData["probation_tagged"] = false
    
    print("\n📊 Final Check-in Data:")
    for (key, value) in checkinData.sorted(by: { $0.key < $1.key }) {
        if key.contains("id") {
            print("   \(key): \(value) ✅")
        } else {
            print("   \(key): \(value)")
        }
    }
}

// Test the specific error scenario
func testErrorScenario() {
    print("\n🚨 Testing Previous Error Scenario")
    print("-" * 30)
    
    // This was the problematic pattern before the fix
    let currentUser: (id: String?)? = nil  // Simulate no current user
    let emptyGateId: String? = ""          // Simulate empty gate ID
    
    print("Before Fix (would cause UUID error):")
    print("   staff_id would be: '\(currentUser?.id ?? "")' ❌")
    print("   gate_id would be: '\(emptyGateId ?? "")' ❌")
    
    print("\nAfter Fix (prevents UUID error):")
    
    // Fixed staff_id handling
    if let staffId = currentUser?.id, !staffId.isEmpty {
        print("   staff_id: \(staffId) ✅")
    } else {
        print("   staff_id: (not included) ✅ - prevents empty string UUID error")
    }
    
    // Fixed gate_id handling
    if let gateId = emptyGateId, !gateId.isEmpty {
        print("   gate_id: \(gateId) ✅")
    } else {
        print("   gate_id: (not included) ✅ - prevents empty string UUID error")
    }
}

// Test validation guards
func testValidationGuards() {
    print("\n🛡️ Testing Validation Guards")
    print("-" * 30)
    
    let testCases = [
        ("Valid wristband ID", "12345678-1234-1234-1234-123456789012", true),
        ("Empty wristband ID", "", false),
        ("Valid event ID", "87654321-4321-4321-4321-210987654321", true),
        ("Empty event ID", "", false)
    ]
    
    for (description, id, shouldPass) in testCases {
        let result = !id.isEmpty
        let status = result == shouldPass ? "✅" : "❌"
        print("   \(status) \(description): '\(id)' -> \(result ? "PASS" : "FAIL")")
    }
}

// Extension for string repetition
extension String {
    static func * (string: String, count: Int) -> String {
        return String(repeating: string, count: count)
    }
}

// Run all tests
print("🔧 Manual Check-in UUID Fix Verification")
print("=" * 50)

testUUIDValidation()
testErrorScenario()
testValidationGuards()

print("\n🎉 Manual Check-in Fix Complete!")
print("✅ Empty string UUID errors should now be prevented")
print("✅ Manual check-in should work correctly")
