import SwiftUI
import CoreNFC

struct SmartScannerView: View {
    @StateObject private var gateService = GateBindingService.shared
    // @StateObject private var locationManager = LocationManager.shared
    
    @State private var isScanning = false
    @State private var lastResult: CheckinPolicyResult?
    @State private var nfcSession: NFCNDEFReaderSession?
    
    var body: some View {
        VStack(spacing: 20) {
            // Gate Status
            gateStatusCard
            
            // Scan Button
            Button(action: startScan) {
                VStack {
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 40))
                    Text("Tap to Scan")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(scanButtonColor)
                .cornerRadius(16)
            }
            .disabled(isScanning)
            
            // Result Card
            if let result = lastResult {
                resultCard(result)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Smart Scanner")
        .onAppear { setupLocation() }
    }
    
    private var gateStatusCard: some View {
        VStack {
            HStack {
                Image(systemName: "location.circle.fill")
                    .foregroundColor(.gray) // locationManager not available
                
                Text(gateService.currentGate?.name ?? "No gate detected")
                    .font(.headline)
                
                Spacer()
            }
            
            Text("Location confidence: \(Int(locationConfidence * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var locationConfidence: Double {
        guard let _ = gateService.currentGate else { return 0.0 }
        return 0.8 // Mock confidence since LocationManager not available
    }
    
    private var scanButtonColor: Color {
        // if !locationManager.isAuthorized { return .gray }
        if locationConfidence < 0.6 { return .orange }
        return .blue
    }
    
    private func resultCard(_ result: CheckinPolicyResult) -> some View {
        VStack(alignment: .leading) {
            Text(result.allowed ? "✅ Access Granted" : "❌ Access Denied")
                .font(.headline)
                .foregroundColor(result.allowed ? .green : .red)
            
            Text(result.reason.displayMessage)
                .font(.subheadline)
        }
        .padding()
        .background(result.allowed ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func setupLocation() {
        // locationManager.requestPermission()
        // locationManager.startUpdating()
        // LocationManager not available - using mock location
    }
    
    private func startScan() {
        guard NFCNDEFReaderSession.readingAvailable else {
            print("NFC not available")
            return
        }
        
        isScanning = true
        // For now, just simulate a scan - real NFC handling will be done through DatabaseScannerViewModel
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.isScanning = false
            // Simulate a policy result
            self.lastResult = CheckinPolicyResult(
                allowed: true,
                reason: .okEnforced,
                locationConfidence: self.locationConfidence,
                warnings: []
            )
        }
    }
}

// NFC handling is done through the GateBindingService and LocationManager
