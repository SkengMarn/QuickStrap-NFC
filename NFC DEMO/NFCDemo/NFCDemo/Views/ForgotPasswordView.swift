import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var supabaseService: SupabaseService
    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        NavigationView {
            ZStack {
                // Background matching AuthenticationView
                LinearGradient(
                    colors: [
                        Color(hex: "#F6F9FC") ?? Color.gray.opacity(0.1),
                        Color.white
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Icon
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#635BFF") ?? .blue)
                                .opacity(0.1)
                                .frame(width: 80, height: 80)

                            Image(systemName: "lock.rotation")
                                .font(.system(size: 35))
                                .foregroundColor(Color(hex: "#635BFF") ?? .blue)
                        }
                        .padding(.top, 20)

                        // Header
                        VStack(spacing: 8) {
                            Text("Forgot Password?")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(Color(hex: "#0A2540") ?? .primary)

                            Text("Enter your email address and we'll send you a link to reset your password")
                                .font(.system(size: 15))
                                .foregroundColor(Color(hex: "#0A2540")?.opacity(0.7) ?? .secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }

                        // Form
                        VStack(spacing: 20) {
                            // Email Field
                            CustomTextField(
                                title: "Email",
                                text: $email,
                                placeholder: "Enter your email",
                                keyboardType: .emailAddress
                            )

                            // Success Message
                            if let successMessage = successMessage {
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)

                                    Text(successMessage)
                                        .font(.system(size: 14))
                                        .foregroundColor(.green)

                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                            }

                            // Error Message
                            if let errorMessage = errorMessage {
                                HStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(Color(hex: "#FF4757") ?? .red)

                                    Text(errorMessage)
                                        .font(.system(size: 14))
                                        .foregroundColor(Color(hex: "#FF4757") ?? .red)

                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(hex: "#FF4757")?.opacity(0.1) ?? .red.opacity(0.1))
                                .cornerRadius(8)
                            }

                            // Send Reset Email Button
                            Button(action: sendResetEmail) {
                                HStack {
                                    if isLoading {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(.white)
                                    }
                                    Text(isLoading ? "Sending..." : "Send Reset Link")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color(hex: "#635BFF") ?? .blue)
                                .cornerRadius(8)
                                .shadow(color: Color(hex: "#635BFF")?.opacity(0.3) ?? .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                            .disabled(isLoading || !isEmailValid)
                            .opacity(isEmailValid ? 1.0 : 0.6)
                        }
                        .padding(.horizontal, 24)

                        Spacer()

                        // Back to Login
                        Button(action: {
                            dismiss()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 13))

                                Text("Back to Login")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(Color(hex: "#635BFF") ?? .blue)
                        }
                        .padding(.bottom, 32)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: - Computed Properties
    private var isEmailValid: Bool {
        !email.isEmpty && email.contains("@")
    }

    // MARK: - Actions
    private func sendResetEmail() {
        guard isEmailValid else { return }

        Task { @MainActor in
            isLoading = true
            errorMessage = nil
            successMessage = nil

            do {
                try await supabaseService.sendPasswordResetEmail(email: email.trimmingCharacters(in: .whitespacesAndNewlines))

                isLoading = false
                successMessage = "Password reset link sent! Check your email."

                // Auto-dismiss after 3 seconds on success
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    dismiss()
                }
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    ForgotPasswordView()
        .environmentObject(SupabaseService.shared)
}
