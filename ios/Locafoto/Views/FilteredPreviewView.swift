import SwiftUI
import AVFoundation
import CoreImage
import MetalKit

/// SwiftUI wrapper for the filtered camera preview
struct FilteredPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    @Binding var currentFilter: CameraFilterPreset
    let onFrameProcessed: ((CIImage) -> Void)?

    init(session: AVCaptureSession, currentFilter: Binding<CameraFilterPreset>, onFrameProcessed: ((CIImage) -> Void)? = nil) {
        self.session = session
        self._currentFilter = currentFilter
        self.onFrameProcessed = onFrameProcessed
    }

    func makeUIView(context: Context) -> MetalPreviewView {
        let view = MetalPreviewView()
        view.session = session
        view.filterPreset = currentFilter
        view.onFrameProcessed = onFrameProcessed
        return view
    }

    func updateUIView(_ uiView: MetalPreviewView, context: Context) {
        uiView.filterPreset = currentFilter
    }
}

/// Metal-backed view for rendering filtered camera frames
class MetalPreviewView: MTKView {
    private var ciContext: CIContext!
    private var commandQueue: MTLCommandQueue!
    private var currentCIImage: CIImage?
    private let filterService = FilterService()

    var session: AVCaptureSession? {
        didSet {
            setupVideoOutput()
        }
    }

    var filterPreset: CameraFilterPreset = .none
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

        commandQueue = metalDevice.makeCommandQueue()
        ciContext = CIContext(mtlDevice: metalDevice, options: [
            .cacheIntermediates: false,
            .priorityRequestLow: false
        ])

        // Configure MTKView
        framebufferOnly = false
        isPaused = true
        enableSetNeedsDisplay = false
        contentMode = .scaleAspectFill
        backgroundColor = .black
    }

    private func setupVideoOutput() {
        guard let session = session else { return }

        // Remove existing video output if any
        if let existingOutput = videoOutput {
            session.removeOutput(existingOutput)
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

            // Set video orientation
            if let connection = output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }
        }
        session.commitConfiguration()
    }

    private func render(_ ciImage: CIImage) {
        guard let currentDrawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let drawableSize = CGSize(width: currentDrawable.texture.width, height: currentDrawable.texture.height)

        // Scale image to fill the drawable while maintaining aspect ratio
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

        // Create CIImage from pixel buffer
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Apply filter
        ciImage = filterService.applyFilter(filterPreset, to: ciImage)

        // Store for potential photo capture
        currentCIImage = ciImage
        onFrameProcessed?(ciImage)

        // Render on main thread
        DispatchQueue.main.async { [weak self] in
            self?.render(ciImage)
        }
    }
}
