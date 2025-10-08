import SwiftUI
import CoreNFC
import Foundation
import Combine

// MARK: - Main App View with Tab Interface
struct ContentView: View {
    @StateObject private var eventData = EventDataManager()
    @StateObject private var nfcReader = NFCReader()
    @StateObject private var supabaseService = SupabaseService.shared
    
    var body: some View {
        Group {
            if !supabaseService.isAuthenticated {
                // Show authentication view
                AuthenticationView()
                    .environmentObject(supabaseService)
            } else if supabaseService.currentEvent != nil {
                // Show main tab interface with navigation
                NavigationView {
                    ThreeTabView(selectedEvent: supabaseService.currentEvent!)
                        .environmentObject(eventData)
                        .environmentObject(nfcReader)
                        .environmentObject(supabaseService)
                }
                .navigationViewStyle(StackNavigationViewStyle())
            } else {
                // Show event selection
                EventSelectionView()
                    .environmentObject(supabaseService)
            }
        }
    }
}

#Preview {
    ContentView()
}
