import SwiftUI

struct GateProcessingBanner: View {
    @StateObject private var processingService = GateProcessingService.shared
    @State private var showingEvents = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main status banner
            if processingService.isProcessing || !processingService.recentEvents.isEmpty {
                statusBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Recent events list (expandable)
            if showingEvents && !processingService.recentEvents.isEmpty {
                eventsListView
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: processingService.isProcessing)
        .animation(.easeInOut(duration: 0.3), value: showingEvents)
    }
    
    // MARK: - Status Banner
    private var statusBanner: some View {
        HStack(spacing: 12) {
            // Processing indicator
            if processingService.isProcessing {
                ProgressView()
                    .scaleEffect(0.8)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else if let latestEvent = processingService.recentEvents.first {
                Image(systemName: latestEvent.icon)
                    .foregroundColor(.white)
                    .font(.system(size: 14, weight: .medium))
            }
            
            // Status text
            VStack(alignment: .leading, spacing: 2) {
                if processingService.isProcessing {
                    Text(processingService.processingStatus)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                } else if let latestEvent = processingService.recentEvents.first {
                    Text(latestEvent.message)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                
                if !processingService.recentEvents.isEmpty {
                    Text("\(processingService.recentEvents.count) recent updates")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            Spacer()
            
            // Expand/collapse button
            if !processingService.recentEvents.isEmpty {
                Button(action: {
                    withAnimation {
                        showingEvents.toggle()
                    }
                }) {
                    Image(systemName: showingEvents ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
            
            // Clear button
            if !processingService.isProcessing && !processingService.recentEvents.isEmpty {
                Button(action: {
                    withAnimation {
                        processingService.clearRecentEvents()
                        showingEvents = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(bannerColor)
        .onTapGesture {
            if !processingService.recentEvents.isEmpty {
                withAnimation {
                    showingEvents.toggle()
                }
            }
        }
    }
    
    // MARK: - Events List
    private var eventsListView: some View {
        VStack(spacing: 0) {
            ForEach(Array(processingService.recentEvents.enumerated()), id: \.offset) { index, event in
                EventRow(event: event, isLatest: index == 0)
                
                if index < processingService.recentEvents.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.2))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(bannerColor.opacity(0.9))
    }
    
    // MARK: - Computed Properties
    private var bannerColor: Color {
        if processingService.isProcessing {
            return Color.blue
        } else if let latestEvent = processingService.recentEvents.first {
            switch latestEvent.color {
            case "blue": return Color.blue
            case "green": return Color.green
            case "orange": return Color.orange
            case "purple": return Color.purple
            case "mint": return Color.mint
            case "indigo": return Color.indigo
            case "gray": return Color.gray
            default: return Color.blue
            }
        }
        return Color.blue
    }
}

// MARK: - Event Row Component
struct EventRow: View {
    let event: GateProcessingEvent
    let isLatest: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: event.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 16)
            
            // Message
            Text(event.message)
                .font(.caption)
                .fontWeight(isLatest ? .medium : .regular)
                .foregroundColor(.white)
                .lineLimit(2)
            
            Spacer()
            
            // Timestamp
            Text(timeAgo)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.vertical, 6)
    }
    
    private var timeAgo: String {
        // For demo purposes, showing "now" - in real app you'd track timestamps
        return isLatest ? "now" : "1m ago"
    }
}

// MARK: - Manual Processing Button
struct ManualProcessingButton: View {
    @StateObject private var processingService = GateProcessingService.shared
    
    var body: some View {
        Button(action: {
            Task {
                await processingService.triggerManualProcessing()
            }
        }) {
            HStack(spacing: 8) {
                if processingService.isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                }
                
                Text(processingService.isProcessing ? "Processing..." : "Refresh Gates")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue)
            .cornerRadius(16)
        }
        .disabled(processingService.isProcessing)
    }
}

#Preview {
    VStack {
        GateProcessingBanner()
        Spacer()
        ManualProcessingButton()
    }
    .background(Color(.systemBackground))
}
