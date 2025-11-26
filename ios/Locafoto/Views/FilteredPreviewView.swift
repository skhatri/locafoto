import SwiftUI
import AVFoundation
import CoreImage
import MetalKit

/// SwiftUI wrapper for the camera preview - receives frames from CameraService
struct FilteredPreviewView: UIViewRepresentable {
    @Binding var currentFilter: CameraFilterPreset
    var viewModel: CameraViewModel

    func makeUIView(context: Context) -> MetalPreviewView {
        let view = MetalPreviewView()
        view.filterPreset = currentFilter
        // Connect preview to viewModel so it receives frames
        viewModel.previewView = view
        return view
    }

    func updateUIView(_ uiView: MetalPreviewView, context: Context) {
        uiView.filterPreset = currentFilter
        // Ensure connection is maintained
        if viewModel.previewView !== uiView {
            viewModel.previewView = uiView
        }
    }
}

/// Metal-backed view for rendering camera frames
class MetalPreviewView: MTKView {
    private var ciContext: CIContext?
    private var commandQueue: MTLCommandQueue?
    private let filterService = FilterService()

    var filterPreset: CameraFilterPreset = .none

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
        isPaused = false
        enableSetNeedsDisplay = false
        contentMode = .scaleAspectFill
        backgroundColor = .black

        delegate = self
    }

    /// Render a frame from CameraService
    func renderFrame(_ ciImage: CIImage) {
        // Apply photo filter for preview if set
        var processedImage = ciImage
        if filterPreset != .none {
            processedImage = filterService.applyFilter(filterPreset, to: ciImage)
        }

        // Render on main thread
        DispatchQueue.main.async { [weak self] in
            self?.render(processedImage)
        }
    }

    private func render(_ ciImage: CIImage) {
        guard let commandQueue = commandQueue,
              let ciContext = ciContext else {
            return
        }

        guard let currentDrawable = currentDrawable else {
            return
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let drawableSize = CGSize(width: currentDrawable.texture.width, height: currentDrawable.texture.height)

        guard !ciImage.extent.isEmpty,
              drawableSize.width > 0,
              drawableSize.height > 0 else {
            return
        }

        // Scale image to fill the drawable while maintaining aspect ratio
        let scaleX = drawableSize.width / ciImage.extent.width
        let scaleY = drawableSize.height / ciImage.extent.height
        let scale = max(scaleX, scaleY)

        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Center the image
        let xOffset = (drawableSize.width - scaledImage.extent.width) / 2
        let yOffset = (drawableSize.height - scaledImage.extent.height) / 2
        let centeredImage = scaledImage.transformed(by: CGAffineTransform(
            translationX: xOffset - scaledImage.extent.origin.x,
            y: yOffset - scaledImage.extent.origin.y
        ))

        // Render
        let bounds = CGRect(origin: .zero, size: drawableSize)
        ciContext.render(centeredImage, to: currentDrawable.texture, commandBuffer: commandBuffer, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())

        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
}

// MARK: - MTKViewDelegate

extension MetalPreviewView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle size changes if needed
    }

    func draw(in view: MTKView) {
        // Frames are rendered via renderFrame() callback
    }
}
