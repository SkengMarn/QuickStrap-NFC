# Complete Gate System Logic & Mathematics

## 📚 Table of Contents
1. [Overview](#overview)
2. [Core Concepts](#core-concepts)
3. [Mathematical Foundations](#mathematical-foundations)
4. [Gate Detection & Creation](#gate-detection--creation)
5. [Gate Binding Logic](#gate-binding-logic)
6. [Deduplication System](#deduplication-system)
7. [Confidence Calculation](#confidence-calculation)
8. [Status Transitions](#status-transitions)
9. [Complete Flow Diagram](#complete-flow-diagram)

---

## Overview

The gate system is a **smart, self-learning** infrastructure that:
- Automatically discovers gates from check-in patterns
- Links wristband categories to gates (called "bindings")
- Learns gate usage patterns over time
- Transitions from "learning mode" (probation) to "trusted mode" (enforced)
- Eliminates duplicate gates caused by GPS drift
- Prevents unauthorized access based on category-gate relationships

**Key Insight**: The system uses **statistical confidence** rather than hard rules, making it adaptable to real-world GPS inaccuracies and varying venue conditions.

---

## Core Concepts

### 1. Gates
A **Gate** represents a physical entry/exit point at an event.

```swift
struct Gate {
    let id: String              // Unique identifier
    let eventId: String          // Which event it belongs to
    let name: String             // e.g., "VIP Entrance", "Main Gate"
    let latitude: Double?        // GPS coordinate
    let longitude: Double?       // GPS coordinate
}
```

**How Gates are Created**:
- **Automatically**: System analyzes check-in patterns and creates gates where scans cluster
- **Manually**: Staff can create gates at specific GPS locations
- **Virtual**: When all scans happen at one location, system creates category-specific virtual gates

### 2. Gate Bindings
A **GateBinding** represents the relationship between a **gate** and a **wristband category**.

```swift
struct GateBinding {
    let gateId: String           // Which gate
    let categoryName: String     // e.g., "VIP", "Staff", "General"
    let status: GateBindingStatus // enforced, probation, or unbound
    let confidence: Double       // 0.0 to 1.0 (statistical confidence)
    let sampleCount: Int         // How many scans contributed to this binding
    let eventId: String
}

enum GateBindingStatus {
    case enforced   // High confidence - strictly enforced
    case probation  // Learning mode - allows access but learning
    case unbound    // No binding exists
}
```

**Example**:
- Gate "VIP Entrance" has a binding to "VIP" category with 95% confidence and "enforced" status
- Gate "Main Entrance" has a binding to "General" category with 72% confidence and "probation" status

### 3. Check-in Logs
Every NFC scan creates a **CheckinLog** with location data.

```swift
struct CheckinLog {
    let wristbandId: String      // e.g., "VIP001"
    let gateId: String?          // Linked gate (null if unlinked)
    let appLat: Double?          // Phone GPS latitude
    let appLon: Double?          // Phone GPS longitude
    let appAccuracy: Double?     // GPS accuracy in meters
    let location: String?        // Text location (e.g., "Manual Check-in - VIP Area")
    let timestamp: Date
}
```

---

## Mathematical Foundations

### 1. Haversine Distance Formula

**Purpose**: Calculate distance between two GPS coordinates on Earth's curved surface.

**Formula**:
```
d = 2R × arcsin(√(a))

Where:
a = sin²(Δφ/2) + cos(φ₁) × cos(φ₂) × sin²(Δλ/2)
R = Earth's radius (6,371,000 meters)
φ = latitude in radians
λ = longitude in radians
Δφ = difference in latitudes
Δλ = difference in longitudes
```

**Implementation**:
```swift
static func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let earthRadiusM = 6371000.0

    let φ1 = lat1 * .pi / 180.0
    let φ2 = lat2 * .pi / 180.0
    let Δφ = (lat2 - lat1) * .pi / 180.0
    let Δλ = (lon2 - lon1) * .pi / 180.0

    let a = sin(Δφ / 2) * sin(Δφ / 2) +
            cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)

    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return earthRadiusM * c
}
```

**Use Cases**:
- Detecting duplicate gates (gates within 25m are likely duplicates)
- Clustering check-ins by location (within 100m)
- Determining if user is near a gate

**Example**:
```
Gate A: (0.354162°, 32.599798°)
Gate B: (0.354170°, 32.599805°)

Distance = 11.2 meters → Likely duplicates!
```

---

### 2. Wilson Score Interval (Lower Bound)

**Purpose**: Calculate **statistical confidence** that a binding is correct, accounting for sample size.

**Why Wilson Score?**
- Simple percentage (k/n) doesn't account for sample size
- 10/10 = 100% but from small sample (unreliable)
- 95/100 = 95% but from large sample (very reliable)
- Wilson score gives **conservative estimate** accounting for uncertainty

**Formula**:
```
Lower Bound = (p̂ + z²/2n - z√(p̂(1-p̂)/n + z²/4n²)) / (1 + z²/n)

Where:
p̂ = k/n (observed proportion)
k = successes (category scans at this gate)
n = total trials (all category scans everywhere)
z = z-score (2.33 for 98% confidence, 1.96 for 95%)
```

**Simplified Implementation**:
```swift
static func wilsonLowerBound(k: Int, n: Int, z: Double = 2.33) -> Double {
    guard n > 0 else { return 0.0 }

    let kDouble = Double(k)
    let nDouble = Double(n)
    let z2 = z * z

    let pHat = (kDouble + z2 / 2) / (nDouble + z2)
    let margin = z * sqrt((pHat * (1 - pHat)) / (nDouble + z2))
    let lowerBound = pHat - margin

    return max(0.0, min(1.0, lowerBound))
}
```

**Real-World Example**:
```
Scenario 1: VIP scans at VIP Gate
- k = 10 (VIP scans at VIP Gate)
- n = 10 (Total VIP scans everywhere)
- Simple %: 10/10 = 100%
- Wilson Score: 78.2% (lower due to small sample)

Scenario 2: VIP scans at VIP Gate (after more data)
- k = 95 (VIP scans at VIP Gate)
- n = 100 (Total VIP scans everywhere)
- Simple %: 95/100 = 95%
- Wilson Score: 89.3% (high confidence due to large sample)

Scenario 3: Noise/Error
- k = 2 (VIP scans at Main Gate - likely error)
- n = 100 (Total VIP scans everywhere)
- Simple %: 2/100 = 2%
- Wilson Score: 0.5% (very low - correctly identifies as noise)
```

**Use Cases**:
- Determining if category should be bound to gate
- Calculating gate binding confidence
- Deciding when to promote from probation to enforced

---

### 3. Location Confidence Score

**Purpose**: Combine multiple location signals (GPS, Bluetooth beacons, WiFi) into single confidence score.

**Formula**:
```
Confidence = wGPS × GPS_trust + wBeacon × Beacon_trust + wWiFi × WiFi_trust

Where:
GPS_trust = max(0, 1 - (GPS_accuracy / GPS_threshold))
Beacon_trust = min(1.0, matched_beacons × 0.3)
WiFi_trust = min(1.0, matched_WiFi × 0.4)

Default weights:
wGPS = 0.4 (40%)
wBeacon = 0.4 (40%)
wWiFi = 0.2 (20%)
```

**Implementation**:
```swift
static func calculateLocationConfidence(
    gpsAccuracyM: Double,
    gpsThresholdM: Double = 20.0,
    matchedBeacons: Int = 0,
    expectedBeacons: Int = 0,
    matchedWiFi: Int = 0,
    expectedWiFi: Int = 0,
    weights: LocationConfidenceWeights = .default
) -> Double {

    // GPS Trust: Better accuracy = higher trust
    let gpsTrust = gpsAccuracyM > 0 && gpsAccuracyM <= gpsThresholdM ?
        max(0.0, 1.0 - (gpsAccuracyM / gpsThresholdM)) : 0.0

    // Beacon Trust: More matched beacons = higher trust
    let beaconTrust = expectedBeacons > 0 ?
        min(1.0, Double(matchedBeacons) * 0.3) : 0.5

    // WiFi Trust: More matched networks = higher trust
    let wifiTrust = expectedWiFi > 0 ?
        min(1.0, Double(matchedWiFi) * 0.4) : 0.3

    return max(0.0, min(1.0,
        weights.gps * gpsTrust +
        weights.beacon * beaconTrust +
        weights.wifi * wifiTrust
    ))
}
```

**Scenario Weights**:
```swift
// Indoor venues: Beacons more reliable than GPS
.indoor = (gps: 0.2, beacon: 0.5, wifi: 0.3)

// Outdoor venues: GPS most reliable
.outdoor = (gps: 0.6, beacon: 0.3, wifi: 0.1)

// Default/Mixed
.default = (gps: 0.4, beacon: 0.4, wifi: 0.2)
```

**Example Calculation**:
```
GPS Accuracy: 8 meters (good)
GPS Threshold: 20 meters
Matched Beacons: 2
Matched WiFi: 1

GPS_trust = 1 - (8/20) = 0.6
Beacon_trust = min(1.0, 2 × 0.3) = 0.6
WiFi_trust = min(1.0, 1 × 0.4) = 0.4

Confidence = 0.4×0.6 + 0.4×0.6 + 0.2×0.4
          = 0.24 + 0.24 + 0.08
          = 0.56 (56% confidence)

Interpretation: Warning level (proceed with caution)
```

---

## Gate Detection & Creation

### Scenario 1: Multiple Location Clustering

**When**: Check-ins spread across multiple distinct GPS locations

**Algorithm**:
```
1. Fetch all check-ins for event
2. Normalize location strings (e.g., "Manual Check-in - VIP" → "vip_area")
3. Group by normalized location string
4. For each group with ≥10 check-ins:
   a. Calculate average GPS coordinates
   b. Extract dominant categories from wristband IDs
   c. Generate smart gate name
   d. Check for duplicates within 25m
   e. If no duplicate: Create new gate
   f. If duplicate exists: Merge into existing gate
```

**Thresholds**:
```swift
struct GateThresholds {
    static let minScansForGateCreation = 10     // Need 10 scans to create gate
    static let minScansForLocationCluster = 10  // Need 10 scans to form cluster
    static let minScansForBinding = 5           // Need 5 scans to bind category
    static let minScansForEnforced = 12         // Need 12 scans for enforced status
    static let deduplicationRadius = 25.0       // 25 meters for duplicate detection
}
```

**Example**:
```
Event has 100 check-ins:
- 45 at "Manual Check-in - VIP Entrance" → Creates "VIP Entrance" gate
- 38 at "Manual Check-in - Main Gate" → Creates "Main Gate" gate
- 12 at "Manual Check-in - Staff Area" → Creates "Staff Gate" gate
- 5 at "Random Location" → Ignored (below threshold)
```

### Scenario 2: Single Location (Virtual Gates)

**When**: 60%+ of check-ins happen within 50 meters of each other

**Algorithm**:
```
1. Detect single location scenario:
   - Calculate GPS coordinates for all check-ins
   - Find how many are within 50m of each other
   - If ≥60%, it's a single location

2. Group check-ins by category (extracted from wristband ID):
   - "VIP001" → VIP
   - "STAFF045" → Staff
   - "GA123" → General

3. For each category with ≥10 scans:
   - Create virtual gate: "{Category} Virtual Gate"
   - Set GPS with slight offset to avoid exact duplicates
   - Create binding with 100% confidence (category-specific gate)
   - Update all check-ins to link to this gate

4. Set cooldown timer (5 minutes) to prevent spam
```

**Example**:
```
Event at single venue (all scans within 50m):
- 30 VIP scans → "VIP Virtual Gate" (100% confidence, enforced)
- 25 Staff scans → "Staff Virtual Gate" (100% confidence, enforced)
- 20 General scans → "General Virtual Gate" (100% confidence, enforced)
- 8 Press scans → Ignored (below 10-scan threshold)
```

**Why Virtual Gates?**
- Indoor events where GPS precision is poor
- All entry happens at one physical location
- Different categories still need separate tracking
- Prevents creating duplicate gates from GPS drift

---

## Gate Binding Logic

### Binding Creation Flow

```
1. Gate created from check-in cluster
   ↓
2. Analyze dominant categories in cluster
   ↓
3. For each category with ≥5 scans:
   a. Calculate Wilson confidence score
   b. Determine initial status
   c. Create GateBinding record
```

### Status Determination

**Formula**:
```
Initial Status = {
    enforced   if confidence ≥ 75% AND scans ≥ 12
    probation  otherwise
}
```

**Code**:
```swift
let confidence = LocationMathService.wilsonLowerBound(
    k: sampleCount,        // Scans at this gate
    n: sampleCount + 10    // Conservative estimate of total
)

let status: GateBindingStatus =
    (confidence >= 0.75 && sampleCount >= 12) ? .enforced : .probation
```

**Example Scenarios**:

```
Scenario A: New gate with few scans
- 8 VIP scans at gate
- Wilson confidence: ~65%
- Status: PROBATION
- Reason: Not enough data yet

Scenario B: Gate with moderate data
- 15 VIP scans at gate
- Wilson confidence: ~78%
- Status: ENFORCED
- Reason: Meets both thresholds (≥12 scans, ≥75% confidence)

Scenario C: Gate with high data
- 50 VIP scans at gate
- Wilson confidence: ~92%
- Status: ENFORCED
- Reason: Very high confidence
```

### Binding Updates

As more check-ins occur, bindings are updated:

```swift
// Fetch existing binding
let existingBinding = await fetchBinding(gateId: gate.id, category: category)

// Update with new data
let newSampleCount = existingBinding.sampleCount + additionalScans
let newConfidence = wilsonLowerBound(k: newSampleCount, n: newSampleCount + 5)

// Determine new status with multiple promotion paths
let shouldEnforce =
    // Path 1: Standard (75% confidence + 12 scans)
    (newConfidence >= 0.75 && newSampleCount >= 12) ||

    // Path 2: High volume (65% confidence + 30 scans)
    (newConfidence >= 0.65 && newSampleCount >= 30) ||

    // Path 3: Probation escape (70% confidence + 20 scans)
    (newConfidence >= 0.70 && newSampleCount >= 20)

let newStatus = shouldEnforce ? .enforced : .probation
```

**Why Multiple Paths?**
- **Path 1**: Standard confidence threshold for typical usage
- **Path 2**: High volume data compensates for slightly lower confidence
- **Path 3**: Allows "escape" from probation with reasonable confidence

---

## Deduplication System

### Why Deduplication is Needed

**GPS Drift Problem**:
```
Real gate at: (0.354162°, 32.599798°)

Check-in scans recorded at:
- Scan 1: (0.354160°, 32.599795°) - 3m away
- Scan 2: (0.354165°, 32.599801°) - 4m away
- Scan 3: (0.354168°, 32.599804°) - 7m away

Without deduplication: Creates 3 gates!
With deduplication: Merges into 1 gate ✓
```

### Duplicate Detection Algorithm

**Step 1: Name Normalization**
```swift
func normalizeGateName(_ name: String) -> String {
    return name.lowercased()
        .replacingOccurrences(of: " gate", with: "")
        .replacingOccurrences(of: "gate", with: "")
        .trimmingCharacters(in: .whitespaces)
}

// "VIP Gate" → "vip"
// "VIP Entrance" → "vip entrance"
// "vip area gate" → "vip area"
```

**Step 2: Group by Normalized Name**
```
Group gates with similar names together:
- "VIP Gate", "VIP Entrance", "vip area" → All grouped as "vip"
- "Main Gate", "Main Entrance" → Grouped as "main entrance"
```

**Step 3: Location-Based Clustering**
```
For each name group:
1. Pick seed gate
2. Find all gates within smart threshold distance
3. Apply merge criteria
4. Create cluster
5. Repeat with remaining ungrouped gates
```

**Smart Thresholds** (venue-aware):
```swift
Indoor venue (<100m spread):   20 meters
Urban venue (100-500m spread): 30 meters
Outdoor venue (>500m spread):  50 meters
```

**Merge Criteria**:
```swift
func shouldMerge(gate1: Gate, gate2: Gate, distance: Double) -> Bool {
    let namesSimilar = areNamesSimilar(gate1.name, gate2.name)
    let withinThreshold = distance <= smartThreshold

    // Strict merge: Both conditions required
    if namesSimilar && withinThreshold {
        return true
    }

    // Aggressive merge: Same name, reasonable distance
    if namesSimilar && distance <= (smartThreshold * 1.5) {
        return true
    }

    return false
}
```

**Example**:
```
Gates to analyze:
1. "VIP Gate" at (0.354162, 32.599798)
2. "VIP Gate" at (0.354168, 32.599804) - 8m away
3. "VIP Entrance" at (0.354165, 32.599801) - 5m away
4. "Staff Gate" at (0.354200, 32.599900) - 50m away

Results:
Cluster 1: Gates 1, 2, 3 (all "vip" related, within 8m)
Cluster 2: Gate 4 (different name, far away)
```

### Cluster Creation

```swift
struct GateCluster {
    let primaryGate: Gate            // First gate (by ID sort)
    let duplicateGates: [Gate]       // Gates to be merged
    let mergedBindings: [GateBinding] // All bindings from all gates
    let averageLocation: (lat, lon)  // Weighted average GPS
    let totalSampleCount: Int        // Sum of all binding samples
    let highestConfidence: Double    // Max confidence from bindings
}
```

**Primary Gate Selection**:
```
Sort gates by ID (chronological)
First gate = Primary
Others = Duplicates to be merged

Why? Oldest gate likely has most historical data
```

**Average Location Calculation**:
```
avgLat = (lat1 + lat2 + lat3) / 3
avgLon = (lon1 + lon2 + lon3) / 3

Updates primary gate to this centroid
```

### Merge Execution

**5-Step Process**:

```
Step 1: Update Primary Gate Location
- Set primary gate GPS to average of all gates in cluster
- Improves position accuracy

Step 2: Merge Bindings
- Collect all bindings from all gates
- Sum sample counts
- Take highest confidence
- Create single merged binding on primary gate

Step 3: Update Check-in Logs
- Find all check-ins referencing duplicate gates
- Update gate_id to reference primary gate
- Preserves historical data

Step 4: Delete Duplicate Gates
- Remove duplicate gates from database
- Only primary gate remains

Step 5: Verify Integrity
- Check no orphaned check-ins exist
- Confirm all gate_id references are valid
```

**Example Merge**:
```
BEFORE:
Gate A (Primary): 20 VIP scans, 85% confidence
Gate B (Duplicate): 15 VIP scans, 78% confidence
Gate C (Duplicate): 10 VIP scans, 72% confidence

AFTER MERGE:
Gate A: 45 VIP scans, 85% confidence (took highest), enforced status
Gate B: DELETED
Gate C: DELETED
All check-ins now reference Gate A
```

---

## Confidence Calculation

### Complete Formula Chain

```
1. Collect Data:
   - k = scans of category X at gate Y
   - n = total scans of category X everywhere

2. Calculate Wilson Score:
   confidence = wilsonLowerBound(k, n, z=2.33)

3. Apply to Binding:
   GateBinding.confidence = confidence

4. Determine Status:
   if (confidence ≥ 0.75 AND k ≥ 12)
       OR (confidence ≥ 0.65 AND k ≥ 30)
       OR (confidence ≥ 0.70 AND k ≥ 20):
       status = .enforced
   else:
       status = .probation
```

### Confidence Evolution Over Time

**Example: VIP Gate Learning Process**

```
Day 1: First VIP scan
- k=1, n=1
- Confidence: 38% (low due to small sample)
- Status: PROBATION
- Action: Allow access, continue learning

Day 2: 5 VIP scans total
- k=5, n=5
- Confidence: 62%
- Status: PROBATION
- Action: Allow access, continue learning

Day 3: 12 VIP scans total
- k=12, n=12
- Confidence: 76%
- Status: ENFORCED (meets 75% + 12 scans threshold)
- Action: Now strictly enforced

Day 5: 30 VIP scans total
- k=30, n=30
- Confidence: 88%
- Status: ENFORCED
- Action: Very high confidence, strict enforcement

---

With noise (VIP scans at wrong gate):
Day 3: 12 VIP scans, but 2 were errors at different gate
- k=10, n=12
- Confidence: 64%
- Status: PROBATION (doesn't meet threshold)
- Action: Continues learning due to inconsistency
```

### Threshold Verification

After deduplication or major changes:

```swift
func verifyThresholds(cluster: GateCluster) -> Result {
    let samples = cluster.totalSampleCount
    let confidence = cluster.highestConfidence

    return Result(
        totalSamples: samples,
        confidence: confidence,
        qualifiesForBinding: samples >= 5,
        qualifiesForEnforced: (samples >= 12 && confidence >= 0.75),
        recommendedStatus: determineStatus(samples, confidence)
    )
}
```

**Output Example**:
```
📊 Threshold Verification:
• Total Samples: 45
• Confidence: 85%
• Qualifies for Binding: ✅ (need 5, have 45)
• Qualifies for Enforced: ✅ (need 12 + 75%, have 45 + 85%)
• Recommended Status: Enforced
```

---

## Status Transitions

### State Machine

```
                    ┌─────────────┐
                    │   UNBOUND   │
                    │  (No data)  │
                    └──────┬──────┘
                           │
                    5+ scans collected
                           │
                           ▼
                    ┌─────────────┐
                ┌───│  PROBATION  │
                │   │ (Learning)  │
                │   └──────┬──────┘
                │          │
                │    Meets thresholds
                │          │
                │          ▼
                │   ┌─────────────┐
                │   │  ENFORCED   │
                │   │  (Trusted)  │
                │   └──────┬──────┘
                │          │
                │    Confidence drops
                │          │
                └──────────┘
```

### Transition Logic

**UNBOUND → PROBATION**:
```
Trigger: 5+ scans of a category at this gate
Action: Create binding with initial confidence
Access: Allow (still learning)
```

**PROBATION → ENFORCED** (Multiple Paths):
```
Path 1 (Standard):
- Confidence ≥ 75% AND Scans ≥ 12

Path 2 (High Volume):
- Confidence ≥ 65% AND Scans ≥ 30

Path 3 (Probation Escape):
- Confidence ≥ 70% AND Scans ≥ 20

Action: Promote to enforced status
Access: Strictly enforce category restrictions
```

**ENFORCED → PROBATION** (Degradation):
```
Trigger:
- Confidence drops below 65% due to errors
- Too many failed scans (different categories)

Action: Demote to probation
Access: Allow but warn
```

### Access Control Based on Status

**Enforced Mode**:
```swift
func evaluateCheckin(category: String, gate: Gate) -> Result {
    let binding = fetchBinding(gate, category)

    if binding == nil {
        return .deny("Category \(category) not bound to \(gate.name)")
    }

    if binding.status == .enforced {
        return .allow("Enforced binding - access granted")
    }

    if binding.status == .probation {
        return .allow("Probation binding - access granted with warning")
    }

    return .deny("Unbound - access denied")
}
```

**Scenario Examples**:
```
Gate: "VIP Entrance"
Bindings:
- VIP: Enforced (95% confidence, 50 scans)
- Staff: Probation (68% confidence, 8 scans)
- General: None

Scan Results:
- VIP wristband → ✅ ALLOWED (enforced binding)
- Staff wristband → ✅ ALLOWED (probation binding, with warning)
- General wristband → ❌ DENIED (no binding)
- Press wristband → ❌ DENIED (no binding)
```

---

## Complete Flow Diagram

### End-to-End System Flow

```
┌──────────────────────────────────────────────────────────────┐
│ 1. CHECK-IN HAPPENS                                          │
├──────────────────────────────────────────────────────────────┤
│ Staff scans NFC wristband "VIP001"                           │
│ Phone GPS: (0.354162, 32.599798) ±8m                        │
│ Location: "Manual Check-in - VIP Entrance"                   │
└────────────────────┬─────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────────┐
│ 2. STORE CHECK-IN LOG                                        │
├──────────────────────────────────────────────────────────────┤
│ Create CheckinLog:                                           │
│ - wristband_id: "VIP001"                                     │
│ - app_lat: 0.354162                                          │
│ - app_lon: 32.599798                                         │
│ - location: "Manual Check-in - VIP Entrance"                 │
│ - gate_id: NULL (not yet linked)                             │
└────────────────────┬─────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────────┐
│ 3. GATE DISCOVERY (Background Process)                       │
├──────────────────────────────────────────────────────────────┤
│ Analyze recent check-ins:                                    │
│                                                              │
│ Location Clustering:                                         │
│ - 15 scans at "VIP Entrance" location                       │
│ - Average GPS: (0.354165, 32.599800)                        │
│ - Dominant category: VIP (extracted from wristband IDs)     │
│                                                              │
│ Decision: CREATE GATE                                        │
│ - Name: "VIP Entrance Gate"                                 │
│ - GPS: (0.354165, 32.599800)                                │
│ - EventID: {current_event}                                  │
└────────────────────┬─────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────────┐
│ 4. DUPLICATE DETECTION                                       │
├──────────────────────────────────────────────────────────────┤
│ Check existing gates within 25m:                             │
│ - No gates found within deduplication radius                 │
│                                                              │
│ Decision: PROCEED WITH GATE CREATION                         │
└────────────────────┬─────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────────┐
│ 5. CREATE GATE BINDING                                       │
├──────────────────────────────────────────────────────────────┤
│ Extract categories from 15 scans:                            │
│ - VIP: 15 scans (100%)                                       │
│                                                              │
│ Calculate Wilson confidence:                                 │
│ - k = 15 (VIP scans at this gate)                           │
│ - n = 15 (total VIP scans everywhere)                       │
│ - confidence = wilsonLowerBound(15, 15) = 82%               │
│                                                              │
│ Determine status:                                            │
│ - confidence (82%) ≥ 75% ✓                                  │
│ - scans (15) ≥ 12 ✓                                         │
│ - Status: ENFORCED                                           │
│                                                              │
│ Create GateBinding:                                          │
│ - gate_id: {new_gate_id}                                    │
│ - category: "VIP"                                            │
│ - status: "enforced"                                         │
│ - confidence: 0.82                                           │
│ - sample_count: 15                                           │
└────────────────────┬─────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────────┐
│ 6. LINK EXISTING CHECK-INS                                   │
├──────────────────────────────────────────────────────────────┤
│ Find unlinked check-ins at this location:                    │
│ - Update all 15 check-ins                                    │
│ - Set gate_id = {new_gate_id}                               │
│                                                              │
│ Result: All VIP check-ins now linked to VIP Entrance Gate   │
└────────────────────┬─────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────────┐
│ 7. FUTURE CHECK-INS                                          │
├──────────────────────────────────────────────────────────────┤
│ New VIP scan at VIP Entrance:                                │
│ - Gate detected: VIP Entrance Gate                           │
│ - Binding exists: VIP → VIP Entrance (enforced)             │
│ - Decision: ✅ ALLOW ACCESS                                  │
│ - Update: sample_count = 16, confidence = 83%               │
│                                                              │
│ New Staff scan at VIP Entrance:                              │
│ - Gate detected: VIP Entrance Gate                           │
│ - Binding exists: VIP only (no Staff binding)               │
│ - Decision: ❌ DENY ACCESS                                   │
│ - Reason: "Staff not authorized for VIP Entrance"           │
│                                                              │
│ New General scan at VIP Entrance:                            │
│ - Gate detected: VIP Entrance Gate                           │
│ - Binding exists: VIP only                                   │
│ - Decision: ❌ DENY ACCESS                                   │
│                                                              │
│ Multiple Staff scans accumulate:                             │
│ - After 5 Staff scans at VIP Entrance                        │
│ - System creates probation binding for Staff                 │
│ - Decision: ✅ ALLOW with warning (learning mode)           │
│ - After 12 more scans (17 total, 75% confidence)            │
│ - Promoted to enforced                                       │
└──────────────────────────────────────────────────────────────┘
```

---

## Summary: How It All Works Together

### The Intelligence Loop

```
1. LEARNING PHASE (Initial state)
   └─> System collects check-in data with GPS and categories
   └─> Clusters form around location patterns
   └─> Gates auto-created when clusters reach threshold
   └─> Bindings start in probation (learning mode)

2. CONFIDENCE BUILDING
   └─> Each check-in adds to sample count
   └─> Wilson score increases with more data
   └─> Inconsistent patterns lower confidence
   └─> Consistent patterns raise confidence

3. ENFORCEMENT PHASE
   └─> Bindings promoted to enforced when thresholds met
   └─> Access control strictly applied
   └─> Unauthorized categories denied
   └─> System continues learning (can demote if confidence drops)

4. OPTIMIZATION PHASE
   └─> Deduplication eliminates GPS-drift duplicates
   └─> Bindings merged for accurate statistics
   └─> Check-ins consolidated to correct gates
   └─> System becomes more accurate over time
```

### Key Design Principles

1. **Statistical Rigor**: Uses Wilson score, not simple percentages
2. **Conservative Estimates**: Lower bounds protect against over-confidence
3. **Gradual Enforcement**: Probation → Enforced transition is data-driven
4. **Self-Healing**: Deduplication automatically fixes GPS drift issues
5. **Venue-Aware**: Smart thresholds adapt to indoor/urban/outdoor contexts
6. **Fail-Safe**: Unknown scenarios default to "allow but learn"

### Real-World Resilience

**Handles GPS Inaccuracy**:
- 25m deduplication radius accounts for GPS drift
- Wilson score reduces impact of outlier scans
- Location clustering smooths coordinate noise

**Handles Mixed Usage**:
- Probation mode allows legitimate multi-category gates
- Confidence drops if inconsistent usage detected
- Multiple promotion paths accommodate different patterns

**Handles Scale**:
- Minimum thresholds prevent premature decisions
- High-volume gates get enforced with lower confidence
- Small gates require higher confidence for enforcement

---

**Version**: 1.0
**Date**: 2025-10-05
**Status**: ✅ Complete Technical Documentation
