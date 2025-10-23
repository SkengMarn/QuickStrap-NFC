import SwiftUI
import LocalAuthentication

struct AuthenticationView: View {
    @EnvironmentObject var supabaseService: SupabaseService
    @State private var isLogin = true
    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var agreedToTerms = false
    @State private var isBiometricAvailable = false
    @State private var showingForgotPassword = false
    
    var body: some View {
        ZStack {
            // Background gradient matching Flutter design
            LinearGradient(
                colors: [
                    Color(hex: "#F6F9FC") ?? Color.gray.opacity(0.1),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Header Section - Compact
                    headerSection
                        .padding(.top, 20)
                    
                    Spacer(minLength: 16)
                    
                    // Form Section - Compact
                    formSection
                    
                    // Biometric Authentication (if available)
                    if isBiometricAvailable {
                        biometricSection
                            .padding(.top, 16)
                    }
                    
                    // Toggle between Login/Register
                    toggleSection
                        .padding(.top, 20)
                    
                    // Biblical Footer - Positioned at bottom with gap
                    Spacer(minLength: 24)
                    
                    VStack(spacing: 8) {
                        Text("Faith by itself, if it does not have works, is dead.")
                            .font(.system(size: 12, design: .serif))
                            .italic()
                            .foregroundColor(Color(hex: "#0A2540")?.opacity(0.6) ?? .secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        Text("James 2:17")
                            .font(.system(size: 10, weight: .light, design: .serif))
                            .italic()
                            .foregroundColor(Color(hex: "#0A2540")?.opacity(0.5) ?? .secondary)
                    }
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            checkBiometricAvailability()
        }
        .sheet(isPresented: $showingForgotPassword) {
            ForgotPasswordView()
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            // App Logo/Icon - Smaller
            ZStack {
                Circle()
                    .fill(Color(hex: "#635BFF") ?? .blue)
                    .frame(width: 70, height: 70)
                    .shadow(color: Color(hex: "#635BFF")?.opacity(0.3) ?? .blue.opacity(0.3), radius: 15, x: 0, y: 6)
                
                Image(systemName: "wave.3.right.circle.fill")
                    .font(.system(size: 35))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 6) {
                Text("QuickStrap NFC")
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .foregroundColor(Color(hex: "#0A2540") ?? .primary)
                
                Text(isLogin ? "Welcome back" : "Create your account")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color(hex: "#0A2540")?.opacity(0.7) ?? .secondary)
            }
        }
    }
    
    // MARK: - Form Section
    private var formSection: some View {
        VStack(spacing: 16) {
            // Email Field
            CustomTextField(
                title: "Email",
                text: $email,
                placeholder: "Enter your email",
                keyboardType: .emailAddress
            )
            
            // Password Field with Forgot Password link
            VStack(alignment: .trailing, spacing: 8) {
                CustomSecureField(
                    title: "Password",
                    text: $password,
                    placeholder: "Enter your password"
                )

                if isLogin {
                    Button(action: {
                        showingForgotPassword = true
                    }) {
                        Text("Forgot Password?")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(hex: "#635BFF") ?? .blue)
                    }
                }
            }
            
            // Registration Fields
            if !isLogin {
                HStack(spacing: 16) {
                    CustomTextField(
                        title: "First Name",
                        text: $firstName,
                        placeholder: "First name"
                    )
                    
                    CustomTextField(
                        title: "Last Name",
                        text: $lastName,
                        placeholder: "Last name"
                    )
                }
                
                // Terms Agreement
                HStack(alignment: .top, spacing: 12) {
                    Button(action: {
                        agreedToTerms.toggle()
                    }) {
                        Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundColor(agreedToTerms ? Color(hex: "#635BFF") ?? .blue : .gray)
                    }
                    
                    Text("I agree to the Terms & Conditions and Privacy Policy")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
                .padding(.top, 8)
            }
            
            // Error Message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#FF4757") ?? .red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(hex: "#FF4757")?.opacity(0.1) ?? .red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            // Submit Button
            Button(action: submitForm) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    }
                    Text(isLoading ? "Please wait..." : (isLogin ? "Sign In" : "Create Account"))
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(hex: "#635BFF") ?? .blue)
                .cornerRadius(8)
                .shadow(color: Color(hex: "#635BFF")?.opacity(0.3) ?? .blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(isLoading || !isFormValid)
            .opacity(isFormValid ? 1.0 : 0.6)
        }
    }
    
    // MARK: - Biometric Section
    private var biometricSection: some View {
        VStack(spacing: 16) {
            HStack {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: 1)
                
                Text("OR")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: 1)
            }
            
            Button(action: authenticateWithBiometrics) {
                HStack(spacing: 12) {
                    Image(systemName: "faceid")
                        .font(.system(size: 20))
                    
                    Text("Sign in with Face ID")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(Color(hex: "#635BFF") ?? .blue)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: "#635BFF") ?? .blue, lineWidth: 1)
                )
            }
            .disabled(isLoading)
        }
    }
    
    // MARK: - Toggle Section
    private var toggleSection: some View {
        HStack(spacing: 4) {
            Text(isLogin ? "Don't have an account?" : "Already have an account?")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "#0A2540") ?? .primary) // Fix: Make text visible
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isLogin.toggle()
                    clearForm()
                }
            }) {
                Text(isLogin ? "Sign Up" : "Sign In")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "#635BFF") ?? .blue)
            }
        }
    }
    
    // MARK: - Computed Properties
    private var isFormValid: Bool {
        let emailValid = !email.isEmpty && email.contains("@")
        let passwordValid = !password.isEmpty && password.count >= 6
        
        if isLogin {
            return emailValid && passwordValid
        } else {
            return emailValid && passwordValid && !firstName.isEmpty && !lastName.isEmpty && agreedToTerms
        }
    }
    
    // MARK: - Actions
    private func submitForm() {
        guard isFormValid else { return }
        
        Task { @MainActor in
            isLoading = true
            errorMessage = nil
            
            do {
                if isLogin {
                    try await supabaseService.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                } else {
                    try await supabaseService.signUp(
                        email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: password,
                        fullName: "\(firstName.trimmingCharacters(in: .whitespacesAndNewlines)) \(lastName.trimmingCharacters(in: .whitespacesAndNewlines))"
                    )
                }
                
                isLoading = false
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        
        isBiometricAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    private func authenticateWithBiometrics() {
        let context = LAContext()
        let reason = "Use Face ID to sign in to QuickStrap NFC"
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            Task { @MainActor in
                if success {
                    // For demo purposes, sign in with stored credentials or show success
                    // In production, you'd retrieve stored credentials from Keychain
                    do {
                        // Check if we have stored credentials first
                        if let storedEmail = try? SecureTokenStorage.retrieve(account: SecureTokenStorage.Account.userEmail),
                           let storedToken = try? SecureTokenStorage.retrieve(account: SecureTokenStorage.Account.accessToken) {
                            
                            // Check if token is still valid
                            if !supabaseService.isTokenExpiredPublic(storedToken) {
                                // Token is still valid, use it directly
                                supabaseService.accessToken = storedToken
                                supabaseService.isAuthenticated = true
                                print("✅ Using valid stored token for: \(storedEmail)")
                            } else {
                                // Token expired, try to refresh
                                print("🔄 Stored token expired, attempting refresh...")
                                if let refreshToken = try? SecureTokenStorage.retrieve(account: SecureTokenStorage.Account.refreshToken) {
                                    try await supabaseService.refreshTokenWithStoredRefreshTokenPublic(refreshToken)
                                    print("✅ Token refreshed successfully for: \(storedEmail)")
                                } else {
                                    // No refresh token, need to re-authenticate
                                    errorMessage = "Session expired. Please sign in again."
                                    return
                                }
                            }
                        } else {
                            // No stored credentials available
                            errorMessage = "No stored credentials found. Please sign in manually."
                            return
                        }
                    } catch {
                        print("❌ Biometric authentication error: \(error)")
                        errorMessage = "Authentication failed: \(error.localizedDescription)"
                    }
                } else {
                    errorMessage = "Biometric authentication failed"
                }
            }
        }
    }
    
    private func clearForm() {
        email = ""
        password = ""
        firstName = ""
        lastName = ""
        errorMessage = nil
        agreedToTerms = false
    }
}

// MARK: - Custom Text Field Components
struct CustomTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "#0A2540") ?? .primary)
            
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .foregroundColor(.black) // Fix: Ensure text is visible
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: "#E9ECEF") ?? .gray.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
    }
}

struct CustomSecureField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    @State private var isSecure = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "#0A2540") ?? .primary)
            
            HStack {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .foregroundColor(.black) // Fix: Ensure password text is visible
                } else {
                    TextField(placeholder, text: $text)
                        .foregroundColor(.black) // Fix: Ensure password text is visible
                }
                
                Button(action: {
                    isSecure.toggle()
                }) {
                    Image(systemName: isSecure ? "eye.slash" : "eye")
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "#E9ECEF") ?? .gray.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
    }
}

// Color extension already defined in DatabaseStatsView.swift

#Preview {
    AuthenticationView()
        .environmentObject(SupabaseService.shared)
}
