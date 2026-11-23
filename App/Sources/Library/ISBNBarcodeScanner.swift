#if os(iOS)
import AVFoundation
import ChickenKit
import SwiftUI
import UIKit

struct ISBNBarcodeScanner: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let onDetected: (String) -> Void

    @State private var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var lastRejectedCode: String?

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()
                switch authorizationStatus {
                case .authorized:
                    scannerContent
                case .notDetermined:
                    ProgressView("Requesting Camera Access…")
                        .tint(palette.ribbon)
                        .foregroundStyle(palette.text)
                case .denied, .restricted:
                    ContentUnavailableView(
                        "Camera Access Required",
                        systemImage: "camera.fill",
                        description: Text("Allow camera access for Chicken in Settings to scan ISBN barcodes.")
                    )
                @unknown default:
                    ContentUnavailableView(
                        "Camera Unavailable",
                        systemImage: "camera.fill",
                        description: Text("This device could not start barcode scanning.")
                    )
                }
            }
            .navigationTitle("Scan ISBN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                if authorizationStatus == .notDetermined {
                    let granted = await AVCaptureDevice.requestAccess(for: .video)
                    authorizationStatus = granted ? .authorized : .denied
                }
            }
        }
    }

    private var scannerContent: some View {
        ZStack(alignment: .bottom) {
            ScannerCameraRepresentable { candidates in
                for raw in candidates {
                    if let normalized = ISBNExtractor.normalize(raw) {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onDetected(normalized)
                        dismiss()
                        return true
                    }
                    lastRejectedCode = raw
                }
                return false
            }
            .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.ribbon, lineWidth: 2)
                .frame(width: 280, height: 150)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            VStack(spacing: 6) {
                Text("Point the camera at a book’s back-cover ISBN barcode")
                    .font(.chickenUI(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                if let lastRejectedCode, !lastRejectedCode.isEmpty {
                    Text("Not an ISBN: \(lastRejectedCode)")
                        .font(.chickenMono(12))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }
}

private struct ScannerCameraRepresentable: UIViewControllerRepresentable {
    let handleBarcodes: @MainActor ([String]) -> Bool

    func makeUIViewController(context: Context) -> BarcodeScannerController {
        let controller = BarcodeScannerController()
        controller.handleBarcodes = handleBarcodes
        return controller
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerController, context: Context) {
        uiViewController.handleBarcodes = handleBarcodes
    }
}

private final class BarcodeScannerController: UIViewController {
    var handleBarcodes: (@MainActor ([String]) -> Bool)?

    private let session = AVCaptureSession()
    private let metadataQueue = DispatchQueue(label: "cyberverse.Chicken.barcodeScanner")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var metadataProxy: MetadataDelegateProxy?
    private var hasDetected = false
    private var isConfigured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasDetected = false
        startRunning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopRunning()
    }

    private func configureSession() {
        guard !isConfigured else { return }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        let proxy = MetadataDelegateProxy { [weak self] codes in
            guard let self, !self.hasDetected else { return }
            if self.handleBarcodes?(codes) == true {
                self.hasDetected = true
                self.stopRunning()
            }
        }
        metadataProxy = proxy
        output.setMetadataObjectsDelegate(proxy, queue: metadataQueue)
        let supported = output.availableMetadataObjectTypes
        var wanted: [AVMetadataObject.ObjectType] = []
        if supported.contains(.ean13) { wanted.append(.ean13) }
        if supported.contains(.ean8) { wanted.append(.ean8) }
        if !wanted.isEmpty {
            output.metadataObjectTypes = wanted
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview
        isConfigured = true
    }

    private func startRunning() {
        guard isConfigured else { return }
        let box = CaptureSessionBox(session)
        metadataQueue.async {
            if !box.session.isRunning {
                box.session.startRunning()
            }
        }
    }

    private func stopRunning() {
        let box = CaptureSessionBox(session)
        metadataQueue.async {
            if box.session.isRunning {
                box.session.stopRunning()
            }
        }
    }
}

nonisolated private final class CaptureSessionBox: @unchecked Sendable {
    let session: AVCaptureSession

    init(_ session: AVCaptureSession) {
        self.session = session
    }
}

private final class MetadataDelegateProxy: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    let onCodes: @MainActor ([String]) -> Void

    init(onCodes: @escaping @MainActor ([String]) -> Void) {
        self.onCodes = onCodes
    }

    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        let codes = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
        guard !codes.isEmpty else { return }
        Task { @MainActor in
            onCodes(codes)
        }
    }
}
#endif
