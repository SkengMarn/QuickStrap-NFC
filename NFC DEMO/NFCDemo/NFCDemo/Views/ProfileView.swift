import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var supabaseService: SupabaseService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Profile Header
                VStack(spacing: 16) {
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#635BFF") ?? .blue)
                            .frame(width: 80, height: 80)
                        
                        Text(initials)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    // User Info
                    if let user = supabaseService.currentUser {
                        VStack(spacing: 8) {
                            Text(user.email)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text(user.role.displayName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color(hex: "#635BFF")?.opacity(0.1) ?? .blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.top, 20)
                
                // Profile Options
                VStack(spacing: 0) {
                    ProfileOption(
                        icon: "envelope",
                        title: "Email",
                        value: supabaseService.currentUser?.email ?? "Not available"
                    )
                    
                    ProfileOption(
                        icon: "person.badge.shield.checkmark",
                        title: "Role",
                        value: supabaseService.currentUser?.role.displayName ?? "Not available"
                    )
                    
                    ProfileOption(
                        icon: "calendar",
                        title: "Member Since",
                        value: memberSinceText
                    )
                    
                    ProfileOption(
                        icon: "building.2",
                        title: "Organization",
                        value: "QuickStrap Solutions"
                    )
                    
                    ProfileOption(
                        icon: "checkmark.shield",
                        title: "Account Status",
                        value: "Active"
                    )
                }
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .background(Color(hex: "#F5F5F5").ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var initials: String {
        guard let email = supabaseService.currentUser?.email else { return "?" }
        let components = email.components(separatedBy: "@")
        let name = components.first ?? email
        return String(name.prefix(2)).uppercased()
    }
    
    private var memberSinceText: String {
        // In a real app, this would come from user creation date
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: Date().addingTimeInterval(-30 * 24 * 60 * 60)) // 30 days ago as example
    }
}

struct ProfileOption: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Color(hex: "#635BFF") ?? .blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    ProfileView()
        .environmentObject(SupabaseService.shared)
}
