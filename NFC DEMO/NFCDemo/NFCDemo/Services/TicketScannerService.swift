import Foundation
import AVFoundation
import SwiftUI

@MainActor
class TicketScannerService: NSObject, ObservableObject {
    static let shared = TicketScannerService()
    
    @Published var isScanning = false
    @Published var scannedCode: String?
    @Published var scanError: String?
    private var errorDismissalTimer: Timer?
    @Published var hasPermission = false
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var onCodeScanned: ((String) -> Void)?
    
    private override init() {
        super.init()
        checkCameraPermission()
    }
    
    // MARK: - Permission Management
    
    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasPermission = true
        case .notDetermined:
            requestCameraPermission()
        case .denied, .restricted:
            hasPermission = false
        @unknown default:
            hasPermission = false
        }
    }
    
    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.hasPermission = granted
            }
        }
    }
    
    // MARK: - Scanner Control
    
    func startScanning(onCodeScanned: @escaping (String) -> Void) {
        guard hasPermission else {
            setScanError("Camera permission required")
            checkCameraPermission() // Re-check permission in case it changed
            return
        }
        
        self.onCodeScanned = onCodeScanned
        setupCaptureSession()
    }
    
    private func setScanError(_ message: String, autoDismissAfter seconds: TimeInterval = 5.0) {
        // Cancel any existing timer
        errorDismissalTimer?.invalidate()
        
        // Set error
        scanError = message
        
        // Auto-dismiss after specified seconds
        errorDismissalTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.clearScanError()
            }
        }
    }
    
    private func clearScanError() {
        errorDismissalTimer?.invalidate()
        errorDismissalTimer = nil
        scanError = nil
    }
    
    func stopScanning() {
        print("🛑 [DEBUG] Stopping scanner...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.stopRunning()
            
            DispatchQueue.main.async {
                self?.captureSession = nil
                self?.previewLayer = nil
                self?.isScanning = false
                self?.onCodeScanned = nil
                self?.clearScanError()
                print("✅ [DEBUG] Scanner stopped successfully")
            }
        }
    }
    
    private func setupCaptureSession() {
        print("🎥 [DEBUG] Setting up capture session...")
        
        // Stop any existing session first
        stopScanning()
        
        captureSession = AVCaptureSession()
        guard let session = captureSession else {
            setScanError("Failed to create capture session")
            return
        }
        
        // Configure session for better performance
        session.sessionPreset = .high
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            setScanError("Camera not available")
            print("❌ [DEBUG] No video capture device found")
            return
        }
        
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            setScanError("Camera input error: \(error.localizedDescription)")
            print("❌ [DEBUG] Failed to create video input: \(error)")
            return
        }
        
        session.beginConfiguration()
        
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
            print("✅ [DEBUG] Video input added successfully")
        } else {
            setScanError("Could not add video input")
            print("❌ [DEBUG] Cannot add video input to session")
            session.commitConfiguration()
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [
                .ean8, .ean13, .pdf417, .qr, .code128, .code39, .code93,
                .upce, .aztec, .dataMatrix, .interleaved2of5, .itf14
            ]
            print("✅ [DEBUG] Metadata output configured with \(metadataOutput.metadataObjectTypes.count) types")
        } else {
            setScanError("Could not add metadata output")
            print("❌ [DEBUG] Cannot add metadata output to session")
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
        
        // Start session on background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            session.startRunning()
            
            DispatchQueue.main.async {
                self?.isScanning = true
                self?.clearScanError()
                print("✅ [DEBUG] Capture session started successfully")
            }
        }
    }
    
    // MARK: - Preview Layer
    
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        guard let captureSession = captureSession else { return nil }
        
        if previewLayer == nil {
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer?.videoGravity = .resizeAspectFill
        }
        
        return previewLayer
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate

extension TicketScannerService: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        
        guard let metadataObject = metadataObjects.first else { return }
        guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
        guard let stringValue = readableObject.stringValue else { return }
        
        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Stop scanning and return result
        stopScanning()
        scannedCode = stringValue
        onCodeScanned?(stringValue)
    }
}

// MARK: - Scanner View Representable

struct TicketScannerView: UIViewRepresentable {
    @ObservedObject var scannerService: TicketScannerService
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black
        
        // Add preview layer when scanner is ready
        updatePreviewLayer(for: view)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update preview layer frame and ensure it's added
        updatePreviewLayer(for: uiView)
    }
    
    private func updatePreviewLayer(for view: UIView) {
        // Remove existing preview layers
        view.layer.sublayers?.removeAll { $0 is AVCaptureVideoPreviewLayer }
        
        // Add current preview layer if available
        if let previewLayer = scannerService.getPreviewLayer() {
            previewLayer.frame = view.bounds
            view.layer.addSublayer(previewLayer)
            print("✅ [DEBUG] Preview layer added to view with frame: \(view.bounds)")
        } else {
            print("⚠️ [DEBUG] No preview layer available")
        }
    }
}

// MARK: - Scanner Overlay View

struct ScannerOverlayView: View {
    let scannerType: TicketCaptureMethod
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
            
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: scannerType.icon)
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                    
                    Text("Scan \(scannerType.displayName)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Position the \(scannerType == .barcode ? "barcode" : "QR code") within the frame")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 60)
                
                Spacer()
                
                // Scanning Frame
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 280, height: 200)
                    .overlay(
                        // Corner indicators
                        VStack {
                            HStack {
                                ScannerCorner()
                                Spacer()
                                ScannerCorner()
                                    .rotationEffect(.degrees(90))
                            }
                            Spacer()
                            HStack {
                                ScannerCorner()
                                    .rotationEffect(.degrees(-90))
                                Spacer()
                                ScannerCorner()
                                    .rotationEffect(.degrees(180))
                            }
                        }
                        .padding(8)
                    )
                
                Spacer()
                
                // Cancel Button
                Button("Cancel") {
                    onCancel()
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.2))
                .cornerRadius(25)
                .padding(.bottom, 60)
            }
        }
        .ignoresSafeArea()
    }
}

struct ScannerCorner: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 20))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 20, y: 0))
        }
        .stroke(Color.orange, lineWidth: 4)
        .frame(width: 20, height: 20)
    }
}
