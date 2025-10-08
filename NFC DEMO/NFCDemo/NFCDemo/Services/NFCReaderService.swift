import Foundation
import CoreNFC
import Combine

// MARK: - NFC Reader Service (Clean implementation)
class NFCReader: NSObject, ObservableObject, NFCNDEFReaderSessionDelegate {
    private var session: NFCNDEFReaderSession?
    var completion: ((String, Bool) -> Void)?
    
    func scan(completion: @escaping (String, Bool) -> Void) {
        self.completion = completion
        guard NFCNDEFReaderSession.readingAvailable else {
            DispatchQueue.main.async {
                completion("", false)
            }
            return
        }
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session?.alertMessage = "Hold your iPhone near the NFC wristband"
        session?.begin()
    }
    
    // Called when NDEF messages are detected
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Take first record first for simplicity
        guard let message = messages.first else {
            completion?("", false)
            return
        }
        
        // Attempt to read textual payload from first record
        if let record = message.records.first {
            let payload = record.payload
            // NDEF text records have a status byte then language code; attempt parsing
            if let text = parseTextPayload(payload) {
                // Here you'd run your validation (e.g., check against backend)
                let isValid = validateWristbandId(text)
                completion?(text, isValid)
                return
            } else {
                // fallback: hex representation
                let hex = payload.map { String(format: "%02X", $0) }.joined()
                let isValid = validateWristbandId(hex)
                completion?(hex, isValid)
                return
            }
        }
        
        completion?("", false)
    }
    
    // Called when session becomes active
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        // Session started - you can update UI if needed
    }
    
    // Called when session invalidates
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // Notify caller; do not treat user cancel as error
        let nsError = error as NSError
        if nsError.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue {
            // user cancelled, return gracefully
            DispatchQueue.main.async {
                self.completion?("", false)
            }
            return
        }
        
        // other errors
        DispatchQueue.main.async {
            self.completion?("", false)
        }
    }
    
    // Helper: parse NDEF text payload (status byte + language code)
    private func parseTextPayload(_ payload: Data) -> String? {
        guard payload.count > 1 else { return nil }
        
        // NDEF Text Record format:
        // Byte 0: Status byte (bit 7 = encoding, bits 5-0 = language code length)
        // Bytes 1 to N: Language code (typically "en")
        // Bytes N+1 to end: Actual text data
        
        let statusByte = payload[0]
        let isUTF16 = (statusByte & 0x80) != 0
        let languageCodeLength = Int(statusByte & 0x3F)
        
        // Calculate start of actual text data
        let textStartIndex = 1 + languageCodeLength
        
        guard payload.count > textStartIndex else { return nil }
        
        // Extract just the text portion, skipping status byte and language code
        let textData = payload.subdata(in: textStartIndex..<payload.count)
        
        // Convert to string using appropriate encoding
        let encoding: String.Encoding = isUTF16 ? .utf16 : .utf8
        let rawText = String(data: textData, encoding: encoding)
        
        // Clean up the text - remove any remaining control characters and whitespace
        return rawText?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
    }
    
    // Placeholder validation - replace with real logic (API call / DB check)
    private func validateWristbandId(_ id: String) -> Bool {
        // Example simple validation: return true if not empty
        // Replace with network call to verify wristband is registered for event
        return !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Legacy Event Data Manager (Simplified for compatibility)
class EventDataManager: ObservableObject {
    @Published var recentScans: [DatabaseScanResult] = []
    
    init() {
        // No mock data - now using real database through SupabaseService
    }
    
    func addScanResult(_ result: DatabaseScanResult) {
        // prepend
        recentScans.insert(result, at: 0)
        // keep recent list to last 200
        if recentScans.count > 200 {
            recentScans.removeLast()
        }
    }
}
