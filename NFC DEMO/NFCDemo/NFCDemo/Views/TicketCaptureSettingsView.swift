import SwiftUI
import Foundation

struct TicketCaptureSettingsView: View {
    @State private var preferences = TicketLinkingPreferences.default
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("Configure how staff will capture ticket information when linking tickets to wristbands.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Ticket Capture Settings")
                }
                
                Section {
                    Picker("Primary Method", selection: $preferences.primaryCaptureMethod) {
                        ForEach(TicketCaptureMethod.allCases, id: \.self) { method in
                            HStack {
                                Image(systemName: method.icon)
                                Text(method.displayName)
                            }
                            .tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Text("The default capture method that will be used when the ticket linking screen opens.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Primary Capture Method")
                }
                
                Section {
                    ForEach(TicketCaptureMethod.allCases, id: \.self) { method in
                        HStack {
                            Image(systemName: method.icon)
                                .foregroundColor(preferences.enabledMethods.contains(method) ? .orange : .secondary)
                                .frame(width: 20)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(method.displayName)
                                    .foregroundColor(.primary)
                                
                                if method.requiresCamera {
                                    Text("Requires camera permission")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { preferences.enabledMethods.contains(method) },
                                set: { enabled in
                                    if enabled {
                                        if !preferences.enabledMethods.contains(method) {
                                            preferences.enabledMethods.append(method)
                                        }
                                    } else {
                                        preferences.enabledMethods.removeAll { $0 == method }
                                        // If we disabled the primary method, switch to search
                                        if preferences.primaryCaptureMethod == method {
                                            preferences.primaryCaptureMethod = .search
                                        }
                                    }
                                }
                            ))
                            .labelsHidden()
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Available Methods")
                } footer: {
                    Text("Enable the capture methods that staff can use. At least one method must be enabled.")
                }
                
                Section {
                    Toggle("Show Method Selector", isOn: $preferences.showMethodSelector)
                    
                    Toggle("Auto-Switch on Failure", isOn: $preferences.autoSwitchOnFailure)
                } header: {
                    Text("Interface Options")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Show Method Selector: Display capture method tabs for staff to choose from")
                        Text("• Auto-Switch on Failure: Automatically try other methods if the primary method finds no results")
                    }
                    .font(.caption)
                }
                
                Section {
                    Button("Reset to Defaults") {
                        preferences = TicketLinkingPreferences.default
                    }
                    .foregroundColor(.orange)
                }
            }
            .navigationTitle("Ticket Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        savePreferences()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(preferences.enabledMethods.isEmpty)
                }
            }
        }
        .onAppear {
            loadPreferences()
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadPreferences() {
        if let savedPreferences = UserDefaults.standard.data(forKey: "TicketLinkingPreferences"),
           let loadedPreferences = try? JSONDecoder().decode(TicketLinkingPreferences.self, from: savedPreferences) {
            preferences = loadedPreferences
        }
    }
    
    private func savePreferences() {
        if let encoded = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(encoded, forKey: "TicketLinkingPreferences")
        }
    }
}

#Preview {
    TicketCaptureSettingsView()
}
