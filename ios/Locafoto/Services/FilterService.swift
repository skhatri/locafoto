import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Metal
import Vision

/// Filter presets available for camera (photos)
enum CameraFilterPreset: String, CaseIterable, Identifiable {
    case none = "None"
    case smoothSkin = "Smooth Skin"
    case softGlow = "Soft Glow"
    case warmTone = "Warm Tone"
    case coolTone = "Cool Tone"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .none: return "circle.slash"
        case .smoothSkin: return "face.smiling"
        case .softGlow: return "sun.max"
        case .warmTone: return "flame"
        case .coolTone: return "snowflake"
        }
    }
}

/// Filter presets available for video recording
enum VideoFilterPreset: String, CaseIterable, Identifiable {
    case none = "None"
    case cinematic = "Cinematic"
    case noir = "Noir"
    case vivid = "Vivid"
    case portrait = "Portrait"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .none: return "circle.slash"
        case .cinematic: return "film"
        case .noir: return "circle.lefthalf.filled"
        case .vivid: return "paintpalette"
        case .portrait: return "person.and.background.dotted"
        }
    }
}

/// Service for applying real-time camera filters using Core Image
final class FilterService {
    private let context: CIContext
    private let segmentationRequest: VNGeneratePersonSegmentationRequest

    init() {
        // Create CIContext with Metal for GPU acceleration
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: metalDevice, options: [
                .cacheIntermediates: false,
                .priorityRequestLow: false
            ])
        } else {
            context = CIContext(options: [.useSoftwareRenderer: false])
        }

        // Create person segmentation request for portrait mode
        segmentationRequest = VNGeneratePersonSegmentationRequest()
        segmentationRequest.qualityLevel = .balanced // Good balance of speed and quality
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    /// Apply filter preset to a CIImage
    func applyFilter(_ preset: CameraFilterPreset, to image: CIImage) -> CIImage {
        switch preset {
        case .none:
            return image

        case .smoothSkin:
            return applySmoothSkinFilter(to: image)

        case .softGlow:
            return applySoftGlowFilter(to: image)

        case .warmTone:
            return applyWarmToneFilter(to: image)

        case .coolTone:
            return applyCoolToneFilter(to: image)
        }
    }

    /// Apply filter to photo data and return filtered data
    func applyFilter(_ preset: CameraFilterPreset, toPhotoData data: Data) -> Data? {
        guard preset != .none else { return data }

        guard let uiImage = UIImage(data: data) else { return nil }

        // Normalize image by drawing it - this applies the orientation to pixel data
        // UIImage.draw() automatically handles orientation
        let size = uiImage.size
        UIGraphicsBeginImageContextWithOptions(size, false, uiImage.scale)
        uiImage.draw(in: CGRect(origin: .zero, size: size))
        guard let normalizedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        UIGraphicsEndImageContext()
        
        // Apply filter to normalized image
        guard let ciImage = CIImage(image: normalizedImage) else { return nil }
        let filteredImage = applyFilter(preset, to: ciImage)

        // Render to CGImage then to JPEG with original orientation preserved
        guard let cgImage = context.createCGImage(filteredImage, from: filteredImage.extent) else {
            return nil
        }

        // Image was already normalized, so use .up orientation
        let finalImage = UIImage(cgImage: cgImage, scale: uiImage.scale, orientation: .up)
        return finalImage.jpegData(compressionQuality: 0.9)
    }

    /// Create CGImage from filtered CIImage for preview rendering
    func createCGImage(from ciImage: CIImage) -> CGImage? {
        return context.createCGImage(ciImage, from: ciImage.extent)
    }

    // MARK: - Video Filter Methods

    /// Apply video filter preset to a CIImage (optimized for real-time)
    func applyVideoFilter(_ preset: VideoFilterPreset, to image: CIImage) -> CIImage {
        switch preset {
        case .none:
            return image

        case .cinematic:
            return applyCinematicFilter(to: image)

        case .noir:
            return applyNoirFilter(to: image)

        case .vivid:
            return applyVividFilter(to: image)

        case .portrait:
            return applyPortraitFilter(to: image)
        }
    }

    /// Cinematic filter - warm tones + contrast for movie look
    private func applyCinematicFilter(to image: CIImage) -> CIImage {
        // Warm color temperature
        let temperature = CIFilter.temperatureAndTint()
        temperature.inputImage = image
        temperature.neutral = CIVector(x: 6500, y: 0)
        temperature.targetNeutral = CIVector(x: 5200, y: 0)

        guard let warmImage = temperature.outputImage else { return image }

        // Boost contrast and slightly reduce brightness for cinematic look
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = warmImage
        colorControls.contrast = 1.15
        colorControls.saturation = 1.1
        colorControls.brightness = -0.02

        return colorControls.outputImage ?? warmImage
    }

    /// Noir filter - high contrast black and white
    private func applyNoirFilter(to image: CIImage) -> CIImage {
        let noir = CIFilter.photoEffectNoir()
        noir.inputImage = image

        guard let noirImage = noir.outputImage else { return image }

        // Boost contrast for dramatic effect
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = noirImage
        colorControls.contrast = 1.2

        return colorControls.outputImage ?? noirImage
    }

    /// Vivid filter - boosted saturation and vibrance
    private func applyVividFilter(to image: CIImage) -> CIImage {
        let vibrance = CIFilter.vibrance()
        vibrance.inputImage = image
        vibrance.amount = 0.5

        guard let vibrantImage = vibrance.outputImage else { return image }

        // Boost saturation and contrast
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = vibrantImage
        colorControls.saturation = 1.25
        colorControls.contrast = 1.08

        return colorControls.outputImage ?? vibrantImage
    }

    /// Portrait filter - blur background while keeping person sharp
    private func applyPortraitFilter(to image: CIImage) -> CIImage {
        // Create handler for the image
        let handler = VNImageRequestHandler(ciImage: image, options: [:])

        do {
            // Perform person segmentation
            try handler.perform([segmentationRequest])

            guard let result = segmentationRequest.results?.first else {
                return image
            }

            // Get the mask as CIImage
            let maskPixelBuffer = result.pixelBuffer
            var maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)

            // Scale mask to match input image size
            let scaleX = image.extent.width / maskImage.extent.width
            let scaleY = image.extent.height / maskImage.extent.height
            maskImage = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

            // Create blurred background
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = image
            blur.radius = 15

            guard let blurredImage = blur.outputImage else { return image }

            // Blend: use mask to composite person over blurred background
            let blendFilter = CIFilter.blendWithMask()
            blendFilter.inputImage = image
            blendFilter.backgroundImage = blurredImage
            blendFilter.maskImage = maskImage

            return blendFilter.outputImage ?? image

        } catch {
            // If segmentation fails, return original image
            return image
        }
    }

    // MARK: - Photo Filter Implementations

    /// Smooth skin filter - subtle blur + sharpen for skin smoothing effect
    private func applySmoothSkinFilter(to image: CIImage) -> CIImage {
        // Step 1: Apply subtle gaussian blur for smoothing
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image
        blur.radius = 2.0

        guard let blurredImage = blur.outputImage else { return image }

        // Step 2: Sharpen luminance to restore detail
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = blurredImage
        sharpen.sharpness = 0.5

        guard let sharpenedImage = sharpen.outputImage else { return blurredImage }

        // Step 3: Slightly boost saturation for healthier skin tones
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = sharpenedImage
        colorControls.saturation = 1.05
        colorControls.brightness = 0.02
        colorControls.contrast = 1.02

        return colorControls.outputImage ?? sharpenedImage
    }

    /// Soft glow filter - dreamy, ethereal look
    private func applySoftGlowFilter(to image: CIImage) -> CIImage {
        // Create a blurred version
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image
        blur.radius = 4.0

        guard let blurredImage = blur.outputImage else { return image }

        // Blend with screen mode for glow effect
        let blend = CIFilter.screenBlendMode()
        blend.inputImage = blurredImage
        blend.backgroundImage = image

        guard let blendedImage = blend.outputImage else { return image }

        // Adjust highlights
        let highlightShadow = CIFilter.highlightShadowAdjust()
        highlightShadow.inputImage = blendedImage
        highlightShadow.highlightAmount = 0.3
        highlightShadow.shadowAmount = -0.1

        return highlightShadow.outputImage ?? blendedImage
    }

    /// Warm tone filter - golden, sunny look
    private func applyWarmToneFilter(to image: CIImage) -> CIImage {
        let temperatureAndTint = CIFilter.temperatureAndTint()
        temperatureAndTint.inputImage = image
        temperatureAndTint.neutral = CIVector(x: 6500, y: 0)
        temperatureAndTint.targetNeutral = CIVector(x: 5000, y: 0) // Warmer

        guard let warmImage = temperatureAndTint.outputImage else { return image }

        // Boost saturation slightly
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = warmImage
        colorControls.saturation = 1.1

        return colorControls.outputImage ?? warmImage
    }

    /// Cool tone filter - blue, crisp look
    private func applyCoolToneFilter(to image: CIImage) -> CIImage {
        let temperatureAndTint = CIFilter.temperatureAndTint()
        temperatureAndTint.inputImage = image
        temperatureAndTint.neutral = CIVector(x: 6500, y: 0)
        temperatureAndTint.targetNeutral = CIVector(x: 8000, y: 0) // Cooler

        guard let coolImage = temperatureAndTint.outputImage else { return image }

        // Increase contrast slightly for crisp look
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = coolImage
        colorControls.contrast = 1.05

        return colorControls.outputImage ?? coolImage
    }
}
