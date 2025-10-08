import SwiftUI

struct ConnectivityStatusView: View {
    @ObservedObject var offlineManager = OfflineDataManager.shared
    
    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(Color(hex: currentStatus.color) ?? .gray)
                .frame(width: 8, height: 8)
            
            // Status text
            Text(currentStatus.displayText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            // Pending sync count
            if offlineManager.pendingSyncCount > 0 {
                Text("(\(offlineManager.pendingSyncCount) pending)")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            
            // Sync button when offline with pending items
            if !offlineManager.isOnline && offlineManager.pendingSyncCount > 0 {
                Button("Retry") {
                    Task {
                        await offlineManager.performManualSync()
                    }
                }
                .font(.caption2)
                .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
    
    private var currentStatus: ConnectivityStatus {
        if offlineManager.isSyncing {
            return .syncing
        } else if offlineManager.isOnline {
            return .online
        } else {
            return .offline
        }
    }
}

// MARK: - Connectivity Banner
struct ConnectivityBanner: View {
    @ObservedObject var offlineManager = OfflineDataManager.shared
    @State private var isVisible = true
    
    var body: some View {
        if shouldShowBanner && isVisible {
            HStack {
                Image(systemName: bannerIcon)
                    .foregroundColor(bannerColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(bannerTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(bannerMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if offlineManager.pendingSyncCount > 0 {
                    Button("Sync Now") {
                        Task {
                            await offlineManager.performManualSync()
                        }
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                Button(action: {
                    withAnimation {
                        isVisible = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(bannerBackgroundColor)
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
    
    private var shouldShowBanner: Bool {
        return !offlineManager.isOnline || offlineManager.pendingSyncCount > 0
    }
    
    private var bannerIcon: String {
        if offlineManager.isSyncing {
            return "arrow.triangle.2.circlepath"
        } else if offlineManager.isOnline && offlineManager.pendingSyncCount > 0 {
            return "exclamationmark.triangle"
        } else {
            return "wifi.slash"
        }
    }
    
    private var bannerTitle: String {
        if offlineManager.isSyncing {
            return "Syncing..."
        } else if offlineManager.isOnline && offlineManager.pendingSyncCount > 0 {
            return "Sync Pending"
        } else {
            return "Offline Mode"
        }
    }
    
    private var bannerMessage: String {
        if offlineManager.isSyncing {
            return "Uploading \(offlineManager.pendingSyncCount) scans"
        } else if offlineManager.isOnline && offlineManager.pendingSyncCount > 0 {
            return "\(offlineManager.pendingSyncCount) scans waiting to sync"
        } else {
            return "Scans will be saved and synced when connected"
        }
    }
    
    private var bannerColor: Color {
        if offlineManager.isSyncing {
            return .orange
        } else if offlineManager.isOnline && offlineManager.pendingSyncCount > 0 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var bannerBackgroundColor: Color {
        if offlineManager.isSyncing {
            return Color.orange.opacity(0.1)
        } else if offlineManager.isOnline && offlineManager.pendingSyncCount > 0 {
            return Color.orange.opacity(0.1)
        } else {
            return Color.red.opacity(0.1)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ConnectivityStatusView()
        ConnectivityBanner()
    }
    .padding()
}
