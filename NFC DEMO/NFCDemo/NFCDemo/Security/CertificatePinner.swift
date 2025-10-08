import Foundation
import Security
import CommonCrypto

/// SSL Certificate Pinning for enhanced security
/// Protects against Man-in-the-Middle attacks
class CertificatePinner: NSObject {
    static let shared = CertificatePinner()

    private let logger = AppLogger.shared

    // Store certificate hashes (SHA-256)
    private var pinnedCertificateHashes: Set<String> = []

    // Configuration
    private let enforcePinning: Bool

    private override init() {
        #if DEBUG
        // Disable pinning in debug for development flexibility
        self.enforcePinning = false
        #else
        // Enable in production
        self.enforcePinning = true
        #endif

        super.init()
        loadPinnedCertificates()
    }

    // MARK: - Configuration

    private func loadPinnedCertificates() {
        // Load pinned certificates from configuration
        // In production, you would add your actual Supabase certificate hashes here

        #if DEBUG
        logger.info("Certificate pinning disabled in debug mode", category: "Security")
        #else
        // Get the certificate hash from your Supabase project
        // You can get this by running:
        // openssl s_client -connect your-project.supabase.co:443 | openssl x509 -pubkey -noout | openssl rsa -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64

        // Example hashes (replace with your actual hashes)
        pinnedCertificateHashes = [
            // Add your Supabase certificate SHA-256 hash here
            // "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
        ]

        if pinnedCertificateHashes.isEmpty {
            logger.warning("No certificates pinned - pinning disabled", category: "Security")
        } else {
            logger.info("Loaded \(pinnedCertificateHashes.count) pinned certificate(s)", category: "Security")
        }
        #endif
    }

    /// Add a certificate hash to the pinned set
    func addPinnedCertificate(hash: String) {
        pinnedCertificateHashes.insert(hash)
        logger.info("Added pinned certificate hash", category: "Security")
    }

    // MARK: - Validation

    /// Validate server trust against pinned certificates
    func validate(
        serverTrust: SecTrust,
        domain: String?
    ) -> Bool {
        // If pinning is disabled or no certificates are pinned, allow all
        guard enforcePinning && !pinnedCertificateHashes.isEmpty else {
            logger.debug("Certificate pinning bypassed (development mode)", category: "Security")
            return true
        }

        // Validate using system trust first
        var error: CFError?
        let isSystemTrusted = SecTrustEvaluateWithError(serverTrust, &error)

        guard isSystemTrusted else {
            logger.error("Server trust validation failed: \(error?.localizedDescription ?? "unknown")", category: "Security")
            return false
        }

        // Get certificate chain
        guard let certificates = extractCertificates(from: serverTrust) else {
            logger.error("Failed to extract certificates from server trust", category: "Security")
            return false
        }

        // Check if any certificate in the chain matches our pinned hashes
        for certificate in certificates {
            if let publicKeyHash = sha256Hash(of: certificate) {
                if pinnedCertificateHashes.contains(publicKeyHash) {
                    logger.info("Certificate pinning validation succeeded", category: "Security")
                    return true
                }
            }
        }

        logger.error("Certificate pinning validation failed - no matching certificate found", category: "Security")
        return false
    }

    // MARK: - Certificate Extraction

    private func extractCertificates(from serverTrust: SecTrust) -> [SecCertificate]? {
        var certificates: [SecCertificate] = []

        // Get certificate count
        let certificateCount = SecTrustGetCertificateCount(serverTrust)

        for index in 0..<certificateCount {
            if let certificate = SecTrustGetCertificateAtIndex(serverTrust, index) {
                certificates.append(certificate)
            }
        }

        return certificates.isEmpty ? nil : certificates
    }

    // MARK: - Hashing

    private func sha256Hash(of certificate: SecCertificate) -> String? {
        // Get public key
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            return nil
        }

        // Get public key data
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return nil
        }

        // Calculate SHA-256 hash
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        publicKeyData.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(publicKeyData.count), &hash)
        }

        // Convert to base64
        let hashData = Data(hash)
        return hashData.base64EncodedString()
    }

    // MARK: - Utility

    /// Get the certificate hash for a given domain (for setup/debugging)
    static func getCertificateHash(for domain: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://\(domain)") else {
            completion(nil)
            return
        }

        let session = URLSession(configuration: .ephemeral, delegate: CertificateHashExtractor { hash in
            completion(hash)
        }, delegateQueue: nil)

        let task = session.dataTask(with: url)
        task.resume()
    }
}

// MARK: - URLSessionDelegate Extension for NetworkClient

extension CertificatePinner: URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let domain = challenge.protectionSpace.host

        if validate(serverTrust: serverTrust, domain: domain) {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            logger.error("Certificate validation failed for domain: \(domain)", category: "Security")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

// MARK: - Helper for extracting certificate hash

private class CertificateHashExtractor: NSObject, URLSessionDelegate {
    let completion: (String?) -> Void

    init(completion: @escaping (String?) -> Void) {
        self.completion = completion
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              let certificate = SecTrustGetCertificateAtIndex(serverTrust, 0),
              let publicKey = SecCertificateCopyKey(certificate),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            completion(nil)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Calculate SHA-256
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        publicKeyData.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(publicKeyData.count), &hash)
        }

        let hashData = Data(hash)
        let hashString = hashData.base64EncodedString()

        completion(hashString)
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}
