import UIKit
import AVFoundation
import CoreImage
import MetalKit
import SwiftUI
import CoreMotion

/// Weak reference wrapper for CADisplayLink to avoid retain cycles
private class WeakDisplayLinkTarget: NSObject {
    weak var target: NativeCameraProcessor?
    
    init(target: NativeCameraProcessor) {
        self.target = target
        super.init()
    }
    
    @objc func handleZoomAnimation() {
        target?.handleZoomAnimation()
    }
}

/// Real-time camera processor that applies filters using CoreImage and Metal.
final class NativeCameraProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Public
    /// The currently selected filter type.
    var selectedFilter: FilterType = FilterType.normal
    
    /// The current zoom factor (1.0 = no zoom, 2.0 = 2x zoom).
    var zoomFactor: CGFloat = 1.0 {
        didSet {
            animateZoom(to: zoomFactor)
        }
    }
    
    /// Whether the flashlight is currently on.
    var isFlashlightOn: Bool = false {
        didSet {
            toggleFlashlight(isFlashlightOn)
        }
    }
    
    /// Whether to use the front camera (true) or back camera (false).
    var useFrontCamera: Bool = false {
        didSet {
            if oldValue != useFrontCamera {
                switchCamera()
            }
        }
    }
    
    /// Whether the camera feed is frozen.
    var isFrozen: Bool = false {
        didSet {
            if isFrozen {
                session.stopRunning()
            } else {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.session.startRunning()
                }
            }
        }
    }
    
    /// Whether the camera is currently switching (shows black screen).
    var isSwitchingCamera: Bool = false {
        didSet {
            // Notify UI about switching state change
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onSwitchingStateChanged?(self.isSwitchingCamera)
            }
        }
    }
    
    /// Callback for switching state changes
    var onSwitchingStateChanged: ((Bool) -> Void)?

    /// Metal view that displays the filtered frames.
    let metalView: MTKView

    // MARK: - Private
    private let session = AVCaptureSession()
    private let ciContext: CIContext
    private let videoQueue = DispatchQueue(label: "camera.video.queue")
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var cameraDevice: AVCaptureDevice?
    private var focusIndicator: UIView?
    
    // For smooth zoom animation
    private var zoomDisplayLink: CADisplayLink?
    private var zoomAnimationStart: CGFloat = 1.0
    private var zoomAnimationEnd: CGFloat = 1.0
    private var zoomAnimationDuration: CFTimeInterval = 0.25
    private var zoomAnimationStartTime: CFTimeInterval = 0.0
    
    // For automatic focus management
    private var motionManager: CMMotionManager?
    private var lastMotionTime: Date = Date()
    private var manualFocusTimer: Timer?
    private var isManualFocusActive = false
    private var lastFocusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5) // Center point
    private var motionThreshold: Double = 0.3 // Sensitivity for motion detection
    private var autoFocusDelay: TimeInterval = 5.0 // Time before returning to auto-focus

    // MARK: - Initialization
    init(selectedFilter: FilterType) {
        // Create Metal device and CIContext
        self.selectedFilter = selectedFilter
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        metalView = MTKView(frame: .zero, device: device)
        metalView.framebufferOnly = false
        metalView.enableSetNeedsDisplay = false
        metalView.isPaused = true // draw() is called manually
        ciContext = CIContext(mtlDevice: device)

        super.init()
        configureCamera()
        setupTapGesture()
        setupFocusIndicator()
        setupMotionManager()
    }

    // MARK: - Camera Configuration
    private func configureCamera() {
        session.beginConfiguration()
        session.sessionPreset = .high

        let position: AVCaptureDevice.Position = useFrontCamera ? .front : .back
        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
            let input = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input)
        else {
            print("❌ Cannot add camera input")
            session.commitConfiguration()
            return
        }

        // Store camera device reference
        self.cameraDevice = camera

        do {
            try camera.lockForConfiguration()

            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                camera.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            camera.unlockForConfiguration()
        } catch {
            print("❌ Failed to configure camera: \(error)")
        }

        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)

        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            print("❌ Cannot add video output")
        }

        session.commitConfiguration()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            // Set initial focus to center after camera starts
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                let centerPoint = CGPoint(x: self.metalView.bounds.midX, y: self.metalView.bounds.midY)
                self.focusAtPoint(centerPoint)
            }
        }
    }

    // MARK: - Frame Processing Delegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Show black screen during camera switching
        if isSwitchingCamera {
            renderBlackScreen()
            return
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciInput = CIImage(cvPixelBuffer: pixelBuffer)
        var ciOutput: CIImage
        
        switch selectedFilter {
        case .normal:
            ciOutput = ciInput
        case .general:
            guard let invertFilter = createFilter(name: "CIColorInvert") else { return }
            invertFilter.setValue(ciInput, forKey: kCIInputImageKey)
            guard let inverted = invertFilter.outputImage else { return }
            guard let exposureFilter = createFilter(name: "CIExposureAdjust") else { return }
            exposureFilter.setValue(inverted, forKey: kCIInputImageKey)
            exposureFilter.setValue(-0.35, forKey: "inputEV")
            guard let exposured = exposureFilter.outputImage else { return }
            guard let contrastFilter = createFilter(name: "CIColorControls") else { return }
            contrastFilter.setValue(exposured, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.4, forKey: "inputContrast")
            contrastFilter.setValue(-0.35, forKey: "inputBrightness")
            contrastFilter.setValue(0.6, forKey: "inputSaturation")
            guard let contrasted = contrastFilter.outputImage else { return }
            guard let toneCurveFilter = createFilter(name: "CIToneCurve") else { return }
            toneCurveFilter.setValue(contrasted, forKey: kCIInputImageKey)
            toneCurveFilter.setValue(CIVector(x: 0.0, y: 0.0), forKey: "inputPoint0")
            toneCurveFilter.setValue(CIVector(x: 0.2, y: 0.1), forKey: "inputPoint1")
            toneCurveFilter.setValue(CIVector(x: 0.4, y: 0.35), forKey: "inputPoint2")
            toneCurveFilter.setValue(CIVector(x: 0.7, y: 0.75), forKey: "inputPoint3")
            toneCurveFilter.setValue(CIVector(x: 1.0, y: 0.95), forKey: "inputPoint4")
            guard let toneCurved = toneCurveFilter.outputImage else { return }
            ciOutput = toneCurved
        case .light:
            guard let invertFilter = CIFilter(name: "CIColorInvert") else { return }
            invertFilter.setValue(ciInput, forKey: kCIInputImageKey)
            guard let inverted = invertFilter.outputImage else { return }
            let exposureFilter = CIFilter(name: "CIExposureAdjust")!
            exposureFilter.setValue(inverted, forKey: kCIInputImageKey)
            exposureFilter.setValue(-0.3, forKey: "inputEV")
            guard let exposured = exposureFilter.outputImage else { return }
            guard let contrastFilter = CIFilter(name: "CIColorControls") else { return }
            contrastFilter.setValue(exposured, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.6, forKey: "inputContrast")
            contrastFilter.setValue(-0.3, forKey: "inputBrightness")
            contrastFilter.setValue(0.5, forKey: "inputSaturation")
            guard let contrasted = contrastFilter.outputImage else { return }
            let toneCurveFilter = CIFilter(name: "CIToneCurve")!
            toneCurveFilter.setValue(contrasted, forKey: kCIInputImageKey)
            toneCurveFilter.setValue(CIVector(x: 0.0, y: 0.0), forKey: "inputPoint0")
            toneCurveFilter.setValue(CIVector(x: 0.15, y: 0.05), forKey: "inputPoint1")
            toneCurveFilter.setValue(CIVector(x: 0.4, y: 0.3), forKey: "inputPoint2")
            toneCurveFilter.setValue(CIVector(x: 0.8, y: 0.85), forKey: "inputPoint3")
            toneCurveFilter.setValue(CIVector(x: 1.0, y: 1.0), forKey: "inputPoint4")
            guard let toneCurved = toneCurveFilter.outputImage else { return }
            ciOutput = toneCurved
        case .dark:
            guard let invertFilter = CIFilter(name: "CIColorInvert") else { return }
            invertFilter.setValue(ciInput, forKey: kCIInputImageKey)
            guard let inverted = invertFilter.outputImage else { return }
            let exposureFilter = CIFilter(name: "CIExposureAdjust")!
            exposureFilter.setValue(inverted, forKey: kCIInputImageKey)
            exposureFilter.setValue(-0.25, forKey: "inputEV")
            guard let exposured = exposureFilter.outputImage else { return }
            guard let contrastFilter = CIFilter(name: "CIColorControls") else { return }
            contrastFilter.setValue(exposured, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.5, forKey: "inputContrast")
            contrastFilter.setValue(-0.25, forKey: "inputBrightness")
            contrastFilter.setValue(0.5, forKey: "inputSaturation")
            guard let contrasted = contrastFilter.outputImage else { return }
            let toneCurveFilter = CIFilter(name: "CIToneCurve")!
            toneCurveFilter.setValue(contrasted, forKey: kCIInputImageKey)
            toneCurveFilter.setValue(CIVector(x: 0.0, y: 0.0), forKey: "inputPoint0")
            toneCurveFilter.setValue(CIVector(x: 0.15, y: 0.08), forKey: "inputPoint1")
            toneCurveFilter.setValue(CIVector(x: 0.4, y: 0.35), forKey: "inputPoint2")
            toneCurveFilter.setValue(CIVector(x: 0.75, y: 0.8), forKey: "inputPoint3")
            toneCurveFilter.setValue(CIVector(x: 1.0, y: 0.98), forKey: "inputPoint4")
            guard let toneCurved = toneCurveFilter.outputImage else { return }
            ciOutput = toneCurved
        case .brown:
            guard let invertFilter = CIFilter(name: "CIColorInvert") else { return }
            invertFilter.setValue(ciInput, forKey: kCIInputImageKey)
            guard let inverted = invertFilter.outputImage else { return }
            let exposureFilter = CIFilter(name: "CIExposureAdjust")!
            exposureFilter.setValue(inverted, forKey: kCIInputImageKey)
            exposureFilter.setValue(-0.28, forKey: "inputEV")
            guard let exposured = exposureFilter.outputImage else { return }
            guard let contrastFilter = CIFilter(name: "CIColorControls") else { return }
            contrastFilter.setValue(exposured, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.45, forKey: "inputContrast")
            contrastFilter.setValue(-0.28, forKey: "inputBrightness")
            contrastFilter.setValue(0.55, forKey: "inputSaturation")
            guard let contrasted = contrastFilter.outputImage else { return }
            let toneCurveFilter = CIFilter(name: "CIToneCurve")!
            toneCurveFilter.setValue(contrasted, forKey: kCIInputImageKey)
            toneCurveFilter.setValue(CIVector(x: 0.0, y: 0.0), forKey: "inputPoint0")
            toneCurveFilter.setValue(CIVector(x: 0.18, y: 0.09), forKey: "inputPoint1")
            toneCurveFilter.setValue(CIVector(x: 0.4, y: 0.37), forKey: "inputPoint2")
            toneCurveFilter.setValue(CIVector(x: 0.72, y: 0.78), forKey: "inputPoint3")
            toneCurveFilter.setValue(CIVector(x: 1.0, y: 0.96), forKey: "inputPoint4")
            guard let toneCurved = toneCurveFilter.outputImage else { return }
            ciOutput = toneCurved
        case .golden:
            guard let invertFilter = CIFilter(name: "CIColorInvert") else { return }
            invertFilter.setValue(ciInput, forKey: kCIInputImageKey)
            guard let inverted = invertFilter.outputImage else { return }
            let exposureFilter = CIFilter(name: "CIExposureAdjust")!
            exposureFilter.setValue(inverted, forKey: kCIInputImageKey)
            exposureFilter.setValue(-0.22, forKey: "inputEV")
            guard let exposured = exposureFilter.outputImage else { return }
            guard let contrastFilter = CIFilter(name: "CIColorControls") else { return }
            contrastFilter.setValue(exposured, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.35, forKey: "inputContrast")
            contrastFilter.setValue(-0.22, forKey: "inputBrightness")
            contrastFilter.setValue(0.65, forKey: "inputSaturation")
            guard let contrasted = contrastFilter.outputImage else { return }
            let toneCurveFilter = CIFilter(name: "CIToneCurve")!
            toneCurveFilter.setValue(contrasted, forKey: kCIInputImageKey)
            toneCurveFilter.setValue(CIVector(x: 0.0, y: 0.0), forKey: "inputPoint0")
            toneCurveFilter.setValue(CIVector(x: 0.22, y: 0.12), forKey: "inputPoint1")
            toneCurveFilter.setValue(CIVector(x: 0.45, y: 0.4), forKey: "inputPoint2")
            toneCurveFilter.setValue(CIVector(x: 0.73, y: 0.77), forKey: "inputPoint3")
            toneCurveFilter.setValue(CIVector(x: 1.0, y: 0.94), forKey: "inputPoint4")
            guard let toneCurved = toneCurveFilter.outputImage else { return }
            ciOutput = toneCurved
        case .gray:
            guard let invertFilter = CIFilter(name: "CIColorInvert") else { return }
            invertFilter.setValue(ciInput, forKey: kCIInputImageKey)
            guard let inverted = invertFilter.outputImage else { return }
            let exposureFilter = CIFilter(name: "CIExposureAdjust")!
            exposureFilter.setValue(inverted, forKey: kCIInputImageKey)
            exposureFilter.setValue(-0.3, forKey: "inputEV")
            guard let exposured = exposureFilter.outputImage else { return }
            guard let contrastFilter = CIFilter(name: "CIColorControls") else { return }
            contrastFilter.setValue(exposured, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.5, forKey: "inputContrast")
            contrastFilter.setValue(-0.3, forKey: "inputBrightness")
            contrastFilter.setValue(0.4, forKey: "inputSaturation")
            guard let contrasted = contrastFilter.outputImage else { return }
            let toneCurveFilter = CIFilter(name: "CIToneCurve")!
            toneCurveFilter.setValue(contrasted, forKey: kCIInputImageKey)
            toneCurveFilter.setValue(CIVector(x: 0.0, y: 0.0), forKey: "inputPoint0")
            toneCurveFilter.setValue(CIVector(x: 0.2, y: 0.1), forKey: "inputPoint1")
            toneCurveFilter.setValue(CIVector(x: 0.4, y: 0.35), forKey: "inputPoint2")
            toneCurveFilter.setValue(CIVector(x: 0.7, y: 0.75), forKey: "inputPoint3")
            toneCurveFilter.setValue(CIVector(x: 1.0, y: 0.95), forKey: "inputPoint4")
            guard let toneCurved = toneCurveFilter.outputImage else { return }
            ciOutput = toneCurved
        case .edge:
            guard let invertFilter = createFilter(name: "CIColorInvert") else { return }
            invertFilter.setValue(ciInput, forKey: kCIInputImageKey)
            guard let inverted = invertFilter.outputImage else { return }
            guard let exposureFilter = createFilter(name: "CIExposureAdjust") else { return }
            exposureFilter.setValue(inverted, forKey: kCIInputImageKey)
            exposureFilter.setValue(-0.2, forKey: "inputEV")
            guard let exposured = exposureFilter.outputImage else { return }
            guard let contrastFilter = createFilter(name: "CIColorControls") else { return }
            contrastFilter.setValue(exposured, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.3, forKey: "inputContrast")
            contrastFilter.setValue(-0.2, forKey: "inputBrightness")
            contrastFilter.setValue(0.7, forKey: "inputSaturation")
            guard let contrasted = contrastFilter.outputImage else { return }
            guard let edgeFilter = createFilter(name: "CIEdges") else { return }
            edgeFilter.setValue(contrasted, forKey: kCIInputImageKey)
            edgeFilter.setValue(2.0, forKey: "inputIntensity") // Softer edge
            guard let edgeImage = edgeFilter.outputImage else { return }
            guard let composite = createFilter(name: "CISourceOverCompositing") else { return }
            composite.setValue(edgeImage, forKey: kCIInputImageKey)
            composite.setValue(contrasted, forKey: kCIInputBackgroundImageKey)
            guard let finalOutput = composite.outputImage else { return }
            ciOutput = finalOutput
        }

        // Render to Metal texture
        guard let drawable = metalView.currentDrawable else { return }
        let transformedImage = ciOutput.oriented(.right)
        
        // Apply horizontal mirroring for front camera AFTER orientation
        var finalImage = transformedImage
        if useFrontCamera {
            let mirrorTransform = CGAffineTransform(scaleX: -1, y: 1)
            finalImage = transformedImage.transformed(by: mirrorTransform)
            // Adjust origin to keep image in bounds
            let translation = CGAffineTransform(translationX: finalImage.extent.width, y: 0)
            finalImage = finalImage.transformed(by: translation)
        }
        let sourceExtent = finalImage.extent
        let targetSize = metalView.drawableSize
        let scaleX = targetSize.width / sourceExtent.width
        let scaleY = targetSize.height / sourceExtent.height
        let scale = max(scaleX, scaleY)
        let scaledImage = finalImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaledImage.extent
        let cropX = (scaledExtent.width - targetSize.width) / 2
        let cropY = (scaledExtent.height - targetSize.height) / 2
        let cropRect = CGRect(x: cropX, y: cropY, width: targetSize.width, height: targetSize.height)
        let croppedImage = scaledImage.cropped(to: cropRect)
        ciContext.render(croppedImage, to: drawable.texture, commandBuffer: nil, bounds: croppedImage.extent, colorSpace: colorSpace)
        // Present the frame
        drawable.present()
        metalView.draw() // Trigger the view to refresh
    }

    /// Safely create a CIFilter with proper error handling
    private func createFilter(name: String) -> CIFilter? {
        guard let filter = CIFilter(name: name) else {
            print("❌ Failed to create filter: \(name)")
            return nil
        }
        return filter
    }
    
    /// Apply a negative LUT to a CIImage using a color cube filter.
    func applyNegativeLUT(to ciImage: CIImage, lutData: Data, dimension: Int = 64) -> CIImage? {
        guard let filter = CIFilter(name: "CIColorCube") else { return nil }
        filter.setValue(dimension, forKey: "inputCubeDimension")
        filter.setValue(lutData, forKey: "inputCubeData")
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        return filter.outputImage
    }

    // MARK: - Tap to Focus
    private func setupTapGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        metalView.addGestureRecognizer(tapGesture)
        metalView.isUserInteractionEnabled = true
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard !isFrozen else { return }
        let location = gesture.location(in: metalView)
        manualFocusAtPoint(location)
    }

    /// Manual focus at a specific point (user tapped)
    private func manualFocusAtPoint(_ point: CGPoint) {
        guard let camera = cameraDevice else { return }
        
        // Cancel any existing timer
        manualFocusTimer?.invalidate()
        
        // Convert screen coordinates to camera coordinates (0,0 to 1,1)
        let focusPoint = CGPoint(
            x: point.y / metalView.bounds.height, // Camera coordinates have inverted y-axis
            y: 1.0 - point.x / metalView.bounds.width
        )
        
        lastFocusPoint = focusPoint
        isManualFocusActive = true
        
        do {
            try camera.lockForConfiguration()
            if camera.isFocusPointOfInterestSupported {
                camera.focusPointOfInterest = focusPoint
                camera.focusMode = .autoFocus
            }
            if camera.isExposurePointOfInterestSupported {
                camera.exposurePointOfInterest = focusPoint
                camera.exposureMode = .autoExpose
            }
            camera.unlockForConfiguration()
            
            // Show focus indicator
            showFocusIndicator(at: point)
            
            // Set timer to return to continuous auto-focus after delay
            manualFocusTimer = Timer.scheduledTimer(withTimeInterval: autoFocusDelay, repeats: false) { [weak self] _ in
                self?.returnToContinuousAutoFocus()
            }
        } catch {
            print("❌ Failed to set focus point: \(error)")
        }
    }
    
    /// Focus the camera at a specific point (automatic or manual)
    private func focusAtPoint(_ point: CGPoint) {
        guard let camera = cameraDevice else { return }
        
        // Convert screen coordinates to camera coordinates (0,0 to 1,1)
        let focusPoint = CGPoint(
            x: point.y / metalView.bounds.height, // Camera coordinates have inverted y-axis
            y: 1.0 - point.x / metalView.bounds.width
        )
        
        lastFocusPoint = focusPoint
        
        do {
            try camera.lockForConfiguration()
            if camera.isFocusPointOfInterestSupported {
                camera.focusPointOfInterest = focusPoint
                camera.focusMode = isManualFocusActive ? .autoFocus : .continuousAutoFocus
            }
            if camera.isExposurePointOfInterestSupported {
                camera.exposurePointOfInterest = focusPoint
                camera.exposureMode = isManualFocusActive ? .autoExpose : .continuousAutoExposure
            }
            camera.unlockForConfiguration()
        } catch {
            print("❌ Failed to set focus point: \(error)")
        }
    }
    
    /// Return to continuous auto-focus mode
    private func returnToContinuousAutoFocus() {
        guard let camera = cameraDevice else { return }
        
        isManualFocusActive = false
        
        do {
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            camera.unlockForConfiguration()
        } catch {
            print("❌ Failed to return to continuous auto-focus: \(error)")
        }
    }

    // MARK: - Zoom Control
    /// Update the camera zoom factor.
    private func updateZoom(factor: CGFloat) {
        guard let camera = cameraDevice else { return }
        do {
            try camera.lockForConfiguration()
            // Clamp zoom factor to camera's supported range
            let maxZoom = camera.activeFormat.videoMaxZoomFactor
            let clampedZoom = min(max(factor, 1.0), maxZoom)
            camera.videoZoomFactor = clampedZoom
            camera.unlockForConfiguration()
        } catch {
            print("❌ Failed to set zoom factor: \(error)")
        }
    }
    
    /// Animate the zoom transition smoothly.
    private func animateZoom(to targetZoom: CGFloat) {
        zoomDisplayLink?.invalidate()
        guard let camera = cameraDevice else { return }
        let currentZoom = camera.videoZoomFactor
        zoomAnimationStart = currentZoom
        zoomAnimationEnd = targetZoom
        zoomAnimationStartTime = CACurrentMediaTime()
        
        // Use weak reference to avoid retain cycle
        let weakTarget = WeakDisplayLinkTarget(target: self)
        zoomDisplayLink = CADisplayLink(target: weakTarget, selector: #selector(WeakDisplayLinkTarget.handleZoomAnimation))
        zoomDisplayLink?.add(to: .main, forMode: .common)
    }
    
    @objc func handleZoomAnimation() {
        let elapsed = CACurrentMediaTime() - zoomAnimationStartTime
        let progress = min(elapsed / zoomAnimationDuration, 1.0)
        // Ease in-out
        let t = CGFloat(-0.5 * (cos(.pi * progress) - 1))
        let newZoom = zoomAnimationStart + (zoomAnimationEnd - zoomAnimationStart) * t
        updateZoom(factor: newZoom)
        if progress >= 1.0 {
            zoomDisplayLink?.invalidate()
            zoomDisplayLink = nil
        }
    }
    
    // MARK: - Focus Indicator
    /// Set up the focus indicator view.
    private func setupFocusIndicator() {
        focusIndicator = UIView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        focusIndicator?.layer.borderWidth = 2.0
        focusIndicator?.layer.borderColor = UIColor(Color.yellow).cgColor
        focusIndicator?.layer.cornerRadius = 30
        focusIndicator?.backgroundColor = UIColor.clear
        focusIndicator?.isHidden = true
        if let indicator = focusIndicator {
            metalView.addSubview(indicator)
        }
    }

    /// Show the focus indicator at a given point with animation.
    private func showFocusIndicator(at point: CGPoint) {
        guard let indicator = focusIndicator else { return }
        indicator.isHidden = true
        indicator.center = point
        indicator.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        indicator.alpha = 1.0
        indicator.isHidden = false
        UIView.animate(withDuration: 0.2, animations: {
            indicator.transform = CGAffineTransform.identity
        }) { _ in
            UIView.animate(withDuration: 0.8, delay: 0.5, options: [], animations: {
                indicator.alpha = 0.0
            }) { _ in
                indicator.isHidden = true
            }
        }
    }

    // MARK: - Motion Management
    private func setupMotionManager() {
        motionManager = CMMotionManager()
        motionManager?.accelerometerUpdateInterval = 0.1 // Update every 100ms
        
        guard motionManager?.isAccelerometerAvailable == true else {
            print("❌ Accelerometer not available")
            return
        }
        
        motionManager?.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data else { return }
            
            let acceleration = data.acceleration
            let currentTime = Date()
            
            // Calculate total acceleration magnitude
            let magnitude = sqrt(acceleration.x * acceleration.x + 
                               acceleration.y * acceleration.y + 
                               acceleration.z * acceleration.z)
            
            // Check if motion is significant
            if magnitude > self.motionThreshold {
                self.lastMotionTime = currentTime
                
                // If we're not in manual focus mode, trigger auto-focus at center
                if !self.isManualFocusActive {
                    let centerPoint = CGPoint(x: self.metalView.bounds.midX, y: self.metalView.bounds.midY)
                    self.focusAtPoint(centerPoint)
                }
            } else {
                // If no significant motion for a while and we're in manual focus, consider returning to auto-focus
                let timeSinceLastMotion = currentTime.timeIntervalSince(self.lastMotionTime)
                if timeSinceLastMotion > self.autoFocusDelay && self.isManualFocusActive {
                    // Only return to auto-focus if no manual focus timer is active
                    if self.manualFocusTimer == nil {
                        self.returnToContinuousAutoFocus()
                    }
                }
            }
        }
    }
    
    // MARK: - Camera Control
    /// Switch between front and back cameras.
    private func switchCamera() {
        // Show black screen during transition
        isSwitchingCamera = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.performCameraSwitch()
        }
    }
    
    private func performCameraSwitch() {
        session.beginConfiguration()
        
        // Remove existing input
        for input in session.inputs {
            session.removeInput(input)
        }
        
        // Add new camera input
        let position: AVCaptureDevice.Position = useFrontCamera ? .front : .back
        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
            let input = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input)
        else {
            print("❌ Cannot switch camera")
            session.commitConfiguration()
            return
        }
        
        session.addInput(input)
        self.cameraDevice = camera
        
        // Configure new camera
        do {
            try camera.lockForConfiguration()
            
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                camera.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            camera.unlockForConfiguration()
        } catch {
            print("❌ Failed to configure switched camera: \(error)")
        }
        
        session.commitConfiguration()
        
        // Turn off flashlight when switching cameras (front camera typically doesn't have flash)
        if useFrontCamera {
            isFlashlightOn = false
        }
        
        // Re-enable camera after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isSwitchingCamera = false
        }
    }
    
    /// Render a black screen during camera switching
    private func renderBlackScreen() {
        guard let drawable = metalView.currentDrawable else { return }
        let targetSize = metalView.drawableSize
        
        // Create a black image
        let blackImage = CIImage(color: CIColor.black).cropped(to: CGRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height))
        
        ciContext.render(blackImage, to: drawable.texture, commandBuffer: nil, bounds: blackImage.extent, colorSpace: colorSpace)
        drawable.present()
        metalView.draw()
    }
    
    /// Toggle the camera flashlight on or off.
    private func toggleFlashlight(_ isOn: Bool) {
        guard let camera = cameraDevice, camera.hasTorch else { return }
        
        do {
            try camera.lockForConfiguration()
            if isOn {
                try camera.setTorchModeOn(level: 1.0)
            } else {
                camera.torchMode = .off
            }
            camera.unlockForConfiguration()
        } catch {
            print("❌ Failed to toggle flashlight: \(error)")
        }
    }
    
    // MARK: - Cleanup
    deinit {
        manualFocusTimer?.invalidate()
        motionManager?.stopAccelerometerUpdates()
        zoomDisplayLink?.invalidate()
        zoomDisplayLink = nil
        session.stopRunning()
    }
}
