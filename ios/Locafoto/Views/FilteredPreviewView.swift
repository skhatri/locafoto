import SwiftUI
import AVFoundation
import CoreImage
import MetalKit

/// SwiftUI wrapper for the filtered camera preview
struct FilteredPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    @Binding var currentFilter: CameraFilterPreset
    @Binding var isUsingFrontCamera: Bool
    let onFrameProcessed: ((CIImage) -> Void)?

    init(session: AVCaptureSession, currentFilter: Binding<CameraFilterPreset>, isUsingFrontCamera: Binding<Bool> = .constant(false), onFrameProcessed: ((CIImage) -> Void)? = nil) {
        self.session = session
        self._currentFilter = currentFilter
        self._isUsingFrontCamera = isUsingFrontCamera
        self.onFrameProcessed = onFrameProcessed
    }

    func makeUIView(context: Context) -> MetalPreviewView {
        let view = MetalPreviewView()
        // Set filter preset first
        view.filterPreset = currentFilter
        view.isUsingFrontCamera = isUsingFrontCamera
        view.onFrameProcessed = onFrameProcessed
        // Set session after view is initialized to trigger setupVideoOutput
        DispatchQueue.main.async {
            view.session = session
        }
        return view
    }

    func updateUIView(_ uiView: MetalPreviewView, context: Context) {
        uiView.filterPreset = currentFilter
        uiView.isUsingFrontCamera = isUsingFrontCamera
    }
}

/// Metal-backed view for rendering filtered camera frames
class MetalPreviewView: MTKView {
    private var ciContext: CIContext?
    private var commandQueue: MTLCommandQueue?
    private var currentCIImage: CIImage?
    private let filterService = FilterService()
    private var isInitialized = false

    var session: AVCaptureSession? {
        didSet {
            // Only setup video output if Metal is properly initialized
            if isInitialized {
                setupVideoOutput()
            }
        }
    }

    var filterPreset: CameraFilterPreset = .none
    var isUsingFrontCamera: Bool = false {
        didSet {
            // Update video orientation on connection after camera switch
            updateVideoConnectionOrientation()
        }
    }
    var onFrameProcessed: ((CIImage) -> Void)?

    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoOutputQueue = DispatchQueue(label: "com.locafoto.videoOutput", qos: .userInteractive)

    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device ?? MTLCreateSystemDefaultDevice())
        commonInit()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        guard let metalDevice = self.device else {
            print("Metal device not available")
            return
        }

        guard let queue = metalDevice.makeCommandQueue() else {
            print("Failed to create Metal command queue")
            return
        }
        
        commandQueue = queue
        
        ciContext = CIContext(mtlDevice: metalDevice, options: [
            .cacheIntermediates: false,
            .priorityRequestLow: false
        ])

        // Configure MTKView
        framebufferOnly = false
        isPaused = false  // Must be false to render frames continuously
        enableSetNeedsDisplay = false
        contentMode = .scaleAspectFill
        backgroundColor = .black
        
        // Set delegate to receive drawable callbacks
        delegate = self
        
        // Mark as initialized
        isInitialized = true
        
        // Setup video output if session is already set
        if session != nil {
            setupVideoOutput()
        }
    }

    private func setupVideoOutput() {
        guard let session = session else { return }
        
        // Ensure we're on the main thread for session configuration
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.setupVideoOutput()
            }
            return
        }

        // Stop session before reconfiguring
        let wasRunning = session.isRunning
        if wasRunning {
            session.stopRunning()
        }

        // Remove existing video output if any
        if let existingOutput = videoOutput {
            session.beginConfiguration()
            session.removeOutput(existingOutput)
            session.commitConfiguration()
            videoOutput = nil
        }

        // Create and configure video data output
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoOutputQueue)

        // Add to session
        session.beginConfiguration()
        if session.canAddOutput(output) {
            session.addOutput(output)
            videoOutput = output

            // Set video orientation based on device orientation
            if let connection = output.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    // Get current device orientation
                    let deviceOrientation = UIDevice.current.orientation
                    let videoOrientation: AVCaptureVideoOrientation
                    
                    switch deviceOrientation {
                    case .portrait:
                        videoOrientation = .portrait
                    case .portraitUpsideDown:
                        videoOrientation = .portraitUpsideDown
                    case .landscapeLeft:
                        videoOrientation = .landscapeRight
                    case .landscapeRight:
                        videoOrientation = .landscapeLeft
                    default:
                        // Default to portrait if unknown
                        videoOrientation = .portrait
                    }
                    
                    connection.videoOrientation = videoOrientation
                }
                
                // Front camera needs mirroring
                if isUsingFrontCamera && connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }
        }
        session.commitConfiguration()
        
        // Restart session if it was running
        if wasRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
        
        // Ensure MTKView is not paused so it can render
        isPaused = false
    }

    private func updateVideoConnectionOrientation() {
        guard let videoOutput = videoOutput,
              let connection = videoOutput.connection(with: .video) else { return }

        if connection.isVideoOrientationSupported {
            // Get current device orientation
            let deviceOrientation = UIDevice.current.orientation
            let videoOrientation: AVCaptureVideoOrientation

            switch deviceOrientation {
            case .portrait:
                videoOrientation = .portrait
            case .portraitUpsideDown:
                videoOrientation = .portraitUpsideDown
            case .landscapeLeft:
                videoOrientation = .landscapeRight
            case .landscapeRight:
                videoOrientation = .landscapeLeft
            default:
                videoOrientation = .portrait
            }

            connection.videoOrientation = videoOrientation
        }

        // Update mirroring for front camera
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = isUsingFrontCamera
        }
    }

    private func render(_ ciImage: CIImage) {
        // Ensure Metal context and command queue are initialized
        guard let commandQueue = commandQueue,
              let ciContext = ciContext else {
            print("Metal not initialized for rendering")
            return
        }
        
        // Get drawable - this might be nil if view isn't ready
        guard let currentDrawable = currentDrawable else {
            // Try to get drawable on next frame
            return
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let drawableSize = CGSize(width: currentDrawable.texture.width, height: currentDrawable.texture.height)
        
        // Ensure valid extent and drawable size
        guard !ciImage.extent.isEmpty, 
              !drawableSize.width.isZero, 
              !drawableSize.height.isZero,
              drawableSize.width > 0,
              drawableSize.height > 0 else {
            return
        }

        // Scale image to fill the drawable while maintaining aspect ratio
        // Note: Image is already rotated and mirrored (if front camera) in captureOutput
        let scaleX = drawableSize.width / ciImage.extent.width
        let scaleY = drawableSize.height / ciImage.extent.height
        let scale = max(scaleX, scaleY)

        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Center the image
        let xOffset = (drawableSize.width - scaledImage.extent.width) / 2
        let yOffset = (drawableSize.height - scaledImage.extent.height) / 2
        let centeredImage = scaledImage.transformed(by: CGAffineTransform(translationX: xOffset - scaledImage.extent.origin.x, y: yOffset - scaledImage.extent.origin.y))

        // Render
        let bounds = CGRect(origin: .zero, size: drawableSize)
        ciContext.render(centeredImage, to: currentDrawable.texture, commandBuffer: commandBuffer, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())

        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension MetalPreviewView: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Ensure Metal context is initialized
        guard ciContext != nil, commandQueue != nil else { return }

        // Create CIImage from pixel buffer
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Note: connection.videoOrientation already handles rotation of the pixel buffer
        // No manual rotation needed here

        // Mirror horizontally for front camera (selfie mode)
        if isUsingFrontCamera {
            let mirrorTransform = CGAffineTransform(scaleX: -1, y: 1)
            let translationX = ciImage.extent.width + ciImage.extent.origin.x * 2
            ciImage = ciImage.transformed(by: mirrorTransform.concatenating(CGAffineTransform(translationX: translationX, y: 0)))
        }

        // Apply filter
        ciImage = filterService.applyFilter(filterPreset, to: ciImage)

        // Store for potential photo capture
        currentCIImage = ciImage
        onFrameProcessed?(ciImage)

        // Render on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.render(ciImage)
        }
    }
}

// MARK: - MTKViewDelegate

extension MetalPreviewView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle size changes if needed
    }
    
    func draw(in view: MTKView) {
        // This is called automatically when isPaused = false
        // We render frames manually in captureOutput, so this can be empty
    }
}
