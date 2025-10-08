import SwiftUI

struct GateDetailsView: View {
    let gate: Gate
    @EnvironmentObject var supabaseService: SupabaseService
    @Environment(\.dismiss) private var dismiss
    
    @State private var checkinLogs: [CheckinLog] = []
    @State private var isLoading = true
    @State private var gateBindings: [GateBinding] = []
    @State private var wristbands: [Wristband] = []
    @State private var uniqueWristbandCount = 0
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Gate Info Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Gate Information")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Name:")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(gate.name)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let location = gate.location {
                                HStack {
                                    Text("Location:")
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text("\(location.latitude, specifier: "%.6f"), \(location.longitude, specifier: "%.6f")")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                                
                                HStack {
                                    Text("Radius:")
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text("\(Int(location.radius))m")
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            HStack {
                                Text("Total Check-ins:")
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(checkinLogs.count)")
                                    .foregroundColor(.blue)
                                    .fontWeight(.bold)
                            }
                            
                            HStack {
                                Text("Unique Wristbands:")
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(uniqueWristbandCount)")
                                    .foregroundColor(.green)
                                    .fontWeight(.bold)
                            }
                        }
                    }
                    .cardStyle()
                    
                    // Gate Bindings Card
                    if !gateBindings.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Category Bindings")
                                .font(.headline)
                            
                            ForEach(gateBindings, id: \.id) { binding in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(binding.categoryName)
                                            .fontWeight(.medium)
                                        Text("\(binding.status.displayName) • \(Int(binding.confidence * 100))% confidence")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Text("\(binding.sampleCount) scans")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(binding.status == .enforced ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                                        .foregroundColor(binding.status == .enforced ? .green : .orange)
                                        .cornerRadius(8)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .cardStyle()
                    }
                    
                    // Check-ins List
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Check-in History (\(checkinLogs.count))")
                            .font(.headline)
                        
                        if isLoading {
                            HStack {
                                Spacer()
                                ProgressView("Loading check-ins...")
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        } else if checkinLogs.isEmpty {
                            Text("No check-ins found for this gate.")
                                .foregroundColor(.secondary)
                                .padding(.vertical, 20)
                        } else {
                            ForEach(checkinLogs.prefix(50), id: \.id) { log in
                                CheckinLogRow(
                                    log: log, 
                                    wristband: wristbands.first { $0.id == log.wristbandId }
                                )
                            }
                            
                            if checkinLogs.count > 50 {
                                Text("Showing first 50 of \(checkinLogs.count) check-ins")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                            }
                        }
                    }
                    .cardStyle()
                }
                .padding()
            }
            .navigationTitle("Gate Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadGateDetails()
        }
    }
    
    private func loadGateDetails() {
        Task {
            await loadCheckinLogs()
            await loadGateBindings()
            await loadWristbands()
        }
    }
    
    private func loadCheckinLogs() async {
        guard let eventId = supabaseService.currentEvent?.id else { return }
        
        do {
            let logs: [CheckinLog] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&gate_id=eq.\(gate.id)&select=*&order=timestamp.desc",
                method: "GET",
                body: nil,
                responseType: [CheckinLog].self
            )
            
            await MainActor.run {
                checkinLogs = logs
                uniqueWristbandCount = Set(logs.map { $0.wristbandId }).count
                isLoading = false
            }
        } catch {
            print("❌ Failed to load check-in logs for gate: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func loadGateBindings() async {
        do {
            let bindings: [GateBinding] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/gate_bindings?gate_id=eq.\(gate.id)&select=*",
                method: "GET",
                body: nil,
                responseType: [GateBinding].self
            )
            
            await MainActor.run {
                gateBindings = bindings
            }
        } catch {
            print("❌ Failed to load gate bindings: \(error)")
        }
    }
    
    private func loadWristbands() async {
        guard let eventId = supabaseService.currentEvent?.id else { return }
        
        // Get unique wristband IDs from check-in logs
        let wristbandIds = Set(checkinLogs.map { $0.wristbandId })
        var fetchedWristbands: [Wristband] = []
        
        for wristbandId in wristbandIds {
            do {
                let wristbandArray: [Wristband] = try await supabaseService.makeRequest(
                    endpoint: "rest/v1/wristbands?id=eq.\(wristbandId)&event_id=eq.\(eventId)&select=*",
                    method: "GET",
                    body: nil,
                    responseType: [Wristband].self
                )
                
                if let wristband = wristbandArray.first {
                    fetchedWristbands.append(wristband)
                }
            } catch {
                print("⚠️ Failed to load wristband \(wristbandId): \(error)")
            }
        }
        
        await MainActor.run {
            self.wristbands = fetchedWristbands
        }
    }
}

struct CheckinLogRow: View {
    let log: CheckinLog
    let wristband: Wristband?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(formatTimestamp(log.timestamp))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if let location = log.location {
                    Text(location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            HStack {
                if let wristband = wristband {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(wristband.category.name) Wristband")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("ID: \(String(log.wristbandId.prefix(8)))...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Wristband: \(String(log.wristbandId.prefix(8)))...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    if let wristband = wristband {
                        Text(wristband.category.name)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(categoryColor(wristband.category.name))
                            .foregroundColor(.white)
                            .cornerRadius(3)
                    }
                    
                    if let lat = log.appLat, let lon = log.appLon {
                        Text("GPS: \(lat, specifier: "%.4f"), \(lon, specifier: "%.4f")")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            if let notes = log.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func formatTimestamp(_ timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    private func categoryColor(_ category: String) -> Color {
        switch category.lowercased() {
        case "vip": return .purple
        case "staff": return .blue
        case "artist": return .red
        case "press": return .green
        case "vendor": return .orange
        case "crew": return .brown
        default: return .gray
        }
    }
}

#Preview {
    GateDetailsView(gate: Gate(
        id: "test",
        eventId: "test-event",
        name: "VIP Gate",
        latitude: 37.7749,
        longitude: -122.4194
    ))
    .environmentObject(SupabaseService.shared)
}
