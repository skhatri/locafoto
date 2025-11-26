import AVFoundation
import UIKit
import CoreImage

/// Service for capturing photos and videos directly without saving to Camera Roll
actor CameraService: NSObject {
    private var photoContinuation: CheckedContinuation<Data, Error>?
    private var videoContinuation: CheckedContinuation<URL, Error>?
    private var currentPosition: AVCaptureDevice.Position = .back

    // Video recording with filters
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var audioDataOutput: AVCaptureAudioDataOutput?
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var tempVideoURL: URL?
    private var isWriting = false
    private var sessionStartTime: CMTime?

    // Filter support
    private let filterService = FilterService()
    private var currentVideoFilter: VideoFilterPreset = .none
    private let ciContext: CIContext

    // Processing queues
    private let videoQueue = DispatchQueue(label: "com.locafoto.videoQueue", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.locafoto.audioQueue", qos: .userInteractive)

    // Frame callback for preview
    private var onPreviewFrame: ((CIImage) -> Void)?

    /// Set the preview callback
    func setPreviewCallback(_ callback: @escaping (CIImage) -> Void) {
        onPreviewFrame = callback
    }

    override init() {
        // Create Metal-backed CIContext for GPU acceleration
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: metalDevice, options: [
                .cacheIntermediates: false,
                .priorityRequestLow: false
            ])
        } else {
            ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }
        super.init()
    }

    /// Set up the camera session for both photo and video capture
    func setupCamera(session: AVCaptureSession, output: AVCapturePhotoOutput, position: AVCaptureDevice.Position = .back) throws {
        currentPosition = position
        session.beginConfiguration()

        // Set session preset for high quality (works for both photo and video)
        session.sessionPreset = .high

        // Get the camera for specified position
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraServiceError.cameraNotAvailable
        }

        // Create input from camera
        let input = try AVCaptureDeviceInput(device: camera)

        // Add video input to session
        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            throw CameraServiceError.cannotAddInput
        }

        // Add audio input for video recording
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            if let audioInput = try? AVCaptureDeviceInput(device: audioDevice) {
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }
            }
        }

        // Add photo output to session
        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            throw CameraServiceError.cannotAddOutput
        }

        // Configure photo output
        output.isHighResolutionCaptureEnabled = true
        if output.availablePhotoCodecTypes.contains(.hevc) {
            // Prefer HEIC format for better compression
            output.setPreparedPhotoSettingsArray([
                AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            ])
        }

        // Add video data output for filtered video recording
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            self.videoDataOutput = videoOutput
        }

        // Add audio data output
        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(self, queue: audioQueue)

        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
            self.audioDataOutput = audioOutput
        }

        // Set mirroring for front camera on ALL outputs
        let shouldMirror = (position == .front)
        for output in session.outputs {
            if let connection = output.connection(with: .video),
               connection.isVideoMirroringSupported {
                connection.isVideoMirrored = shouldMirror
            }
        }

        session.commitConfiguration()

        // Start the session on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    /// Flip camera between front and back
    func flipCamera(session: AVCaptureSession, output: AVCapturePhotoOutput) throws {
        let newPosition: AVCaptureDevice.Position = (currentPosition == .back) ? .front : .back

        session.beginConfiguration()

        // Remove existing input
        if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
            session.removeInput(currentInput)
        }

        // Get camera for new position
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
            session.commitConfiguration()
            throw CameraServiceError.cameraNotAvailable
        }

        // Add new input
        let newInput = try AVCaptureDeviceInput(device: camera)
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            currentPosition = newPosition
        } else {
            session.commitConfiguration()
            throw CameraServiceError.cannotAddInput
        }

        // Set mirroring for front camera on ALL outputs
        let shouldMirror = (newPosition == .front)
        for output in session.outputs {
            if let connection = output.connection(with: .video),
               connection.isVideoMirroringSupported {
                connection.isVideoMirrored = shouldMirror
            }
        }

        session.commitConfiguration()
    }

    /// Get current camera position
    func getCurrentPosition() -> AVCaptureDevice.Position {
        return currentPosition
    }

    /// Stop the camera session
    func stopCamera(session: AVCaptureSession) {
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }

    /// Capture a photo and return the data
    /// IMPORTANT: This never saves to Camera Roll!
    func capturePhoto(output: AVCapturePhotoOutput) async throws -> Data {
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else {
                continuation.resume(throwing: CameraServiceError.captureFailed)
                return
            }

            Task {
                await self.setPhotoContinuation(continuation)

                // Use HEIC if available for better compression
                let settings: AVCapturePhotoSettings
                if output.availablePhotoCodecTypes.contains(.hevc) {
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                    settings.isHighResolutionPhotoEnabled = true
                } else {
                    settings = AVCapturePhotoSettings()
                    settings.isHighResolutionPhotoEnabled = true
                }
                
                // Set photo orientation to portrait
                if let connection = output.connection(with: .video) {
                    if connection.isVideoOrientationSupported {
                        // Get current device orientation
                        let deviceOrientation = UIDevice.current.orientation
                        let photoOrientation: AVCaptureVideoOrientation
                        
                        switch deviceOrientation {
                        case .portrait:
                            photoOrientation = .portrait
                        case .portraitUpsideDown:
                            photoOrientation = .portraitUpsideDown
                        case .landscapeLeft:
                            photoOrientation = .landscapeRight
                        case .landscapeRight:
                            photoOrientation = .landscapeLeft
                        default:
                            photoOrientation = .portrait
                        }
                        
                        connection.videoOrientation = photoOrientation
                    }
                }

                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func setPhotoContinuation(_ continuation: CheckedContinuation<Data, Error>) {
        self.photoContinuation = continuation
    }

    // MARK: - Video Recording

    /// Set the video filter for recording
    func setVideoFilter(_ filter: VideoFilterPreset) {
        currentVideoFilter = filter
    }

    /// Get current video filter
    func getVideoFilter() -> VideoFilterPreset {
        return currentVideoFilter
    }

    /// Start recording video with filter
    func startRecording() async throws {
        guard let videoDataOutput = videoDataOutput else {
            throw CameraServiceError.videoOutputNotAvailable
        }

        guard !isWriting else {
            return
        }

        // Create temp file URL for recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + ".mov"
        let fileURL = tempDir.appendingPathComponent(fileName)
        tempVideoURL = fileURL

        // Remove existing file if any
        try? FileManager.default.removeItem(at: fileURL)

        // Create asset writer
        assetWriter = try AVAssetWriter(outputURL: fileURL, fileType: .mov)

        // Get video dimensions and orientation from connection
        guard let connection = videoDataOutput.connection(with: .video) else {
            throw CameraServiceError.videoOutputNotAvailable
        }

        // Get actual dimensions from video output
        let videoDimensions = CMVideoFormatDescriptionGetDimensions(
            connection.inputPorts.first?.formatDescription ??
            (videoDataOutput.connections.first?.inputPorts.first?.formatDescription)!
        )

        // Use portrait dimensions (swap width/height for portrait recording)
        let videoWidth = Int(videoDimensions.height)
        let videoHeight = Int(videoDimensions.width)

        // Configure video input with correct dimensions
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 10_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput?.expectsMediaDataInRealTime = true

        // Create pixel buffer adaptor for filtered frames
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: videoWidth,
            kCVPixelBufferHeightKey as String: videoHeight
        ]

        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput!,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        if assetWriter!.canAdd(videoWriterInput!) {
            assetWriter!.add(videoWriterInput!)
        }

        // Configure audio input
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]

        audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioWriterInput?.expectsMediaDataInRealTime = true

        if assetWriter!.canAdd(audioWriterInput!) {
            assetWriter!.add(audioWriterInput!)
        }

        // Start writing
        assetWriter!.startWriting()
        isWriting = true
        sessionStartTime = nil
    }

    /// Stop recording and return the video URL
    func stopRecording() async throws -> URL {
        guard isWriting else {
            throw CameraServiceError.notRecording
        }

        isWriting = false

        return try await withCheckedThrowingContinuation { continuation in
            self.videoContinuation = continuation

            // Mark inputs as finished
            videoWriterInput?.markAsFinished()
            audioWriterInput?.markAsFinished()

            // Finish writing
            assetWriter?.finishWriting { [weak self] in
                guard let self = self else { return }

                Task {
                    await self.handleWritingFinished()
                }
            }
        }
    }

    private func handleWritingFinished() {
        guard let continuation = videoContinuation else { return }
        videoContinuation = nil

        if let error = assetWriter?.error {
            continuation.resume(throwing: error)
        } else if let url = tempVideoURL {
            continuation.resume(returning: url)
        } else {
            continuation.resume(throwing: CameraServiceError.recordingFailed)
        }

        // Clean up
        assetWriter = nil
        videoWriterInput = nil
        audioWriterInput = nil
        pixelBufferAdaptor = nil
        sessionStartTime = nil
    }

    /// Check if currently recording
    func isRecording() -> Bool {
        return isWriting
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate & AVCaptureAudioDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        Task {
            await processSampleBuffer(sampleBuffer, from: output)
        }
    }

    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, from output: AVCaptureOutput) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if output == videoDataOutput {
            // Always process video frame for preview
            processVideoFrame(sampleBuffer, timestamp: timestamp)
        } else if output == audioDataOutput {
            // Only process audio when recording
            if isWriting {
                processAudioSample(sampleBuffer)
            }
        }
    }

    private func processVideoFrame(_ sampleBuffer: CMSampleBuffer, timestamp: CMTime) {
        // Get pixel buffer from sample
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // Create CIImage from pixel buffer
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Rotate for portrait orientation
        // Camera sensor is landscape, we want portrait output
        // Front camera data is mirrored, so needs opposite rotation
        if currentPosition == .front {
            ciImage = ciImage.oriented(.left)
        } else {
            ciImage = ciImage.oriented(.right)
        }

        // Normalize extent to origin (0,0) after orientation transform
        // This ensures consistent rendering in Metal preview
        if ciImage.extent.origin != .zero {
            ciImage = ciImage.transformed(by: CGAffineTransform(
                translationX: -ciImage.extent.origin.x,
                y: -ciImage.extent.origin.y
            ))
        }

        // Apply video filter if recording with filter, or photo filter for preview
        if isWriting && currentVideoFilter != .none {
            ciImage = filterService.applyVideoFilter(currentVideoFilter, to: ciImage)
        }

        // Send to preview callback
        onPreviewFrame?(ciImage)

        // Write to recording if active
        if isWriting,
           let assetWriter = assetWriter,
           assetWriter.status == .writing,
           let videoWriterInput = videoWriterInput,
           let pixelBufferAdaptor = pixelBufferAdaptor,
           videoWriterInput.isReadyForMoreMediaData {

            // Start session on first frame
            if sessionStartTime == nil {
                sessionStartTime = timestamp
                assetWriter.startSession(atSourceTime: timestamp)
            }

            // Render to pixel buffer for recording
            if let outputBuffer = createPixelBuffer(from: ciImage, adaptor: pixelBufferAdaptor) {
                pixelBufferAdaptor.append(outputBuffer, withPresentationTime: timestamp)
            }
        }
    }

    private func processAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard let audioWriterInput = audioWriterInput,
              audioWriterInput.isReadyForMoreMediaData else {
            return
        }

        audioWriterInput.append(sampleBuffer)
    }

    private func createPixelBuffer(from ciImage: CIImage, adaptor: AVAssetWriterInputPixelBufferAdaptor) -> CVPixelBuffer? {
        guard let pool = adaptor.pixelBufferPool else { return nil }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        // Ensure image extent is at origin (0,0) for rendering
        // Note: processVideoFrame already normalizes the extent, but filters may change it
        let renderImage = ciImage.extent.origin == .zero ? ciImage : ciImage.transformed(by: CGAffineTransform(
            translationX: -ciImage.extent.origin.x,
            y: -ciImage.extent.origin.y
        ))

        ciContext.render(renderImage, to: buffer)
        return buffer
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task {
            await handlePhotoCapture(photo: photo, error: error)
        }
    }

    private func handlePhotoCapture(photo: AVCapturePhoto, error: Error?) {
        guard let continuation = photoContinuation else { return }
        photoContinuation = nil

        if let error = error {
            continuation.resume(throwing: error)
            return
        }

        // Get the photo data - THIS STAYS IN MEMORY, never saved to Camera Roll
        guard let imageData = photo.fileDataRepresentation() else {
            continuation.resume(throwing: CameraServiceError.noImageData)
            return
        }

        // Return the data - it will be encrypted and saved to app container
        continuation.resume(returning: imageData)
    }
}

// MARK: - Errors

enum CameraServiceError: LocalizedError {
    case cameraNotAvailable
    case cannotAddInput
    case cannotAddOutput
    case noImageData
    case captureFailed
    case videoOutputNotAvailable
    case notRecording
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .cameraNotAvailable:
            return "Camera is not available"
        case .cannotAddInput:
            return "Cannot add camera input to session"
        case .cannotAddOutput:
            return "Cannot add photo output to session"
        case .noImageData:
            return "Failed to get image data from photo"
        case .captureFailed:
            return "Camera capture failed"
        case .videoOutputNotAvailable:
            return "Video output is not available"
        case .notRecording:
            return "Not currently recording"
        case .recordingFailed:
            return "Video recording failed"
        }
    }
}
