# Gates Tab Flow Chart

## Complete Flow of Gate Management System

```mermaid
flowchart TD
    A[App Opens] --> B[Gates Tab Selected]
    B --> C[Load Data Process Starts]
    
    C --> D{Current Event Selected?}
    D -->|No| E[Show Error: No Event]
    D -->|Yes| F[Fetch Active Gates with Scans]
    
    F --> G[Query Database for Gates with Scan Count > 0]
    G --> H[Filter Out Empty Gates]
    H --> I[Load Gate Bindings]
    I --> J[Load Check-in Counts]
    
    J --> K[Start Automatic Processing]
    K --> L[Background Timer: Every 30s]
    
    L --> M[Automatic Processing Cycle]
    M --> N[Process New Scans]
    M --> O[Detect Duplicates]
    M --> P[Promote Gates]
    M --> Q[Update Quality Scores]
    
    %% New Scan Processing
    N --> N1[Check Recent Scans (Last 5 min)]
    N1 --> N2{New Scans Found?}
    N2 -->|Yes| N3[Show: 📍 New scan at Gate Name]
    N2 -->|No| N4[Continue Processing]
    N3 --> N5[Update Gate Binding Confidence]
    N5 --> N4
    
    %% Duplicate Detection
    O --> O1[Find Gate Clusters within 50m]
    O1 --> O2{Duplicates Found?}
    O2 -->|Yes| O3[Show: 🔍 Duplicate detected]
    O2 -->|No| O4[Continue Processing]
    O3 --> O5{Confidence > 80%?}
    O5 -->|Yes| O6[Auto-merge Gates]
    O5 -->|No| O7[Mark for Manual Review]
    O6 --> O8[Show: 🔄 Merged Gate A into Gate B]
    O8 --> O4
    O7 --> O4
    
    %% Gate Promotion
    P --> P1[Check Gate Binding Status]
    P1 --> P2{Meets Promotion Criteria?}
    P2 -->|Yes| P3[Promote Gate Status]
    P2 -->|No| P4[Keep Current Status]
    P3 --> P5[Show: ⬆️ Gate promoted: probation → confirmed]
    P5 --> P4
    
    %% Quality Updates
    Q --> Q1[Calculate Gate Quality Score]
    Q1 --> Q2{Quality Improved > 10%?}
    Q2 -->|Yes| Q3[Show: 📈 Gate quality improved]
    Q2 -->|No| Q4[Continue Processing]
    Q3 --> Q4
    
    %% UI Display Logic
    N4 --> R[Update UI State]
    O4 --> R
    P4 --> R
    Q4 --> R
    
    R --> S[Display Processing Banner]
    S --> T{Gates with Scans > 0?}
    T -->|No| U[Show: No Active Gates Message]
    T -->|Yes| V[Display Gates List]
    
    V --> W[Show Status Cards]
    W --> X[Confirmed Gates Count]
    W --> Y[Probation Gates Count]  
    W --> Z[Duplicates Count]
    
    V --> AA[Show Gate Rows]
    AA --> BB[Gate Name & Location]
    AA --> CC[Binding Status Badge]
    AA --> DD[Confidence Percentage]
    AA --> EE[Sample Count]
    
    %% User Interactions
    V --> FF[User Interactions]
    FF --> GG[Tap Refresh Button]
    FF --> HH[Pull to Refresh]
    FF --> II[Tap Gate Row]
    
    GG --> JJ[Manual Processing Trigger]
    HH --> JJ
    JJ --> M
    
    II --> KK[Navigate to Gate Details]
    KK --> LL[Show Scan History]
    KK --> MM[Show Statistics]
    KK --> NN[Show Activity Chart]
    
    %% Background Maintenance
    L --> OO[Background Maintenance]
    OO --> PP[Auto-merge High Confidence Duplicates]
    OO --> QQ[Promote Qualifying Gates]
    OO --> RR[Clean up Dead Gates]
    
    PP --> SS{Confidence > 75%?}
    SS -->|Yes| TT[Execute Merge]
    SS -->|No| UU[Skip Merge]
    TT --> VV[Update Database]
    VV --> UU
    
    QQ --> WW{Sample Count ≥ 15 & Confidence ≥ 75%?}
    WW -->|Yes| XX[Promote to Enforced]
    WW -->|No| YY{Sample Count ≥ 5 & Confidence ≥ 60%?}
    YY -->|Yes| ZZ[Promote to Probation]
    YY -->|No| AAA[Keep Unbound]
    XX --> BBB[Update Status in DB]
    ZZ --> BBB
    BBB --> AAA
    
    RR --> CCC[Find Gates with < 5 Samples]
    CCC --> DDD{Gate Age > 24 hours?}
    DDD -->|Yes| EEE[Mark for Cleanup]
    DDD -->|No| FFF[Keep Gate]
    EEE --> GGG[Log Cleanup Action]
    GGG --> FFF
    
    %% Error Handling
    F --> HHH{API Error?}
    HHH -->|Yes| III[Show Fallback Method]
    HHH -->|No| J
    III --> JJJ[Fetch All Gates]
    JJJ --> KKK[Filter Manually]
    KKK --> J
    
    %% Processing Status Updates
    M --> LLL[Show: 🔄 Processing gate updates...]
    N4 --> MMM[Show: ✅ Gate processing completed]
    O4 --> MMM
    P4 --> MMM
    Q4 --> MMM
    
    style A fill:#e1f5fe
    style M fill:#fff3e0
    style V fill:#e8f5e8
    style FF fill:#fce4ec
    style OO fill:#f3e5f5
    style HHH fill:#ffebee
```

## Key Components Breakdown

### 1. **Data Loading Flow**
- Checks for current event selection
- Fetches only gates with actual scans (filters out empty gates)
- Loads gate bindings and check-in counts
- Handles API errors with fallback methods

### 2. **Automatic Processing (Every 30 seconds)**
- **New Scan Detection**: Monitors for scans in last 5 minutes
- **Duplicate Detection**: Finds gates within 50m radius
- **Auto-merging**: Merges duplicates with >80% confidence
- **Gate Promotion**: Upgrades status based on confidence thresholds
- **Quality Monitoring**: Tracks and reports quality improvements

### 3. **UI Display Logic**
- Shows processing status banner
- Displays "No Active Gates" if no scans found
- Shows status cards (Confirmed, Probation, Duplicates)
- Lists gate rows with binding info and confidence

### 4. **User Interactions**
- **Refresh Button**: Triggers manual processing
- **Pull to Refresh**: Reloads data
- **Tap Gate Row**: Navigate to detailed view (when implemented)

### 5. **Background Maintenance**
- **Auto-merge**: High confidence duplicates (>75%)
- **Promotion Logic**: 
  - Probation → Enforced: 15+ samples + 75% confidence
  - Unbound → Probation: 5+ samples + 60% confidence
- **Cleanup**: Remove gates with <5 samples after 24 hours

### 6. **Real-time Notifications**
- 📍 "New scan at [Gate Name]"
- 🔍 "Duplicate detected: [Gate A] matches [Gate B]"
- 🔄 "Merged [Gate A] into [Gate B]"
- ⬆️ "Gate promoted: probation → confirmed"
- 📈 "Gate quality improved to [X]%"
- 🔄 "Processing gate updates..."
- ✅ "Gate processing completed"

### 7. **Error Handling**
- API failures trigger fallback methods
- Graceful degradation to manual filtering
- User feedback for processing states

## Gate Status Promotion Criteria

| Status | Requirements | Action |
|--------|-------------|--------|
| **Unbound** → **Probation** | 5+ samples + 60% confidence | Auto-promote |
| **Probation** → **Enforced** | 15+ samples + 75% confidence | Auto-promote |
| **High Volume** → **Enforced** | 30+ samples + 65% confidence | Auto-promote |

## Duplicate Detection Logic

1. **Proximity Check**: Gates within 50m radius
2. **Confidence Calculation**: Based on location accuracy and sample count
3. **Auto-merge Threshold**: >80% confidence
4. **Manual Review**: 60-80% confidence range
5. **Ignore**: <60% confidence

This flowchart shows the complete automated gate management system that runs continuously in your app! 🎯
