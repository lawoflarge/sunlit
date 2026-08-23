import AVFoundation
import SwiftUI
import UIKit

// MARK: - Access

/// Whether the camera may be used, and why not when it may not.
///
/// Every one of these states has a screen behind it. A refused camera is a
/// review item, not an edge case: the view has to explain itself, offer the
/// way back, and keep working without the image.
enum CameraAccess: Equatable {
    case undetermined
    case authorised
    case denied
    case restricted
    /// There is no back camera at all. The simulator, and nothing this app
    /// ships to.
    case unavailable

    var allowsCapture: Bool { self == .authorised }
}

// MARK: - Optics

/// The lens geometry the overlay projection needs.
///
/// The field of view is read from the format the capture device is actually
/// running, never assumed. It differs by several degrees across iPhone models
/// and between formats on one model, and a wrong value does not blur the
/// overlay, it moves the sun off target by a visible amount at the edges of
/// the frame.
struct CameraOptics: Equatable {

    /// Field of view across the buffer's long axis, in degrees, as
    /// `AVCaptureDevice.Format.videoFieldOfView` reports it.
    var fieldOfViewDegrees: Double
    /// Buffer size in pixels, in the sensor's own landscape orientation, so
    /// `bufferWidth` is the long axis and the one `fieldOfViewDegrees` spans.
    var bufferWidth: Double
    var bufferHeight: Double
    /// True when these came from a real capture device rather than the
    /// assumption below.
    var isMeasured: Bool

    /// What the overlay uses when there is no camera to ask: no device, or a
    /// device that refused to report a format.
    ///
    /// This is a display choice and not a measurement, which is why
    /// `isMeasured` is false and why the interface says the overlay is drawn
    /// without a camera image whenever it is in force. Sixty eight degrees is
    /// the wide camera on the iPhone models this app targets, and with no
    /// image behind the curves an error here changes only how much sky fits on
    /// the screen.
    static let assumed = CameraOptics(
        fieldOfViewDegrees: 68,
        bufferWidth: 1920,
        bufferHeight: 1080,
        isMeasured: false)

    /// The pinhole focal length in buffer pixels.
    ///
    /// A rectilinear lens maps an angle `theta` off the optical axis to a
    /// distance `f * tan(theta)` from the centre of the image. Half the buffer
    /// width therefore subtends half the field of view, which gives
    /// `f = (width / 2) / tan(fov / 2)` and fixes the scale of the whole
    /// projection with one number.
    var focalLengthPixels: Double {
        let clamped = min(max(fieldOfViewDegrees, 20), 140)
        let halfAngle = clamped / 2 * .pi / 180
        return (bufferWidth / 2) / tan(halfAngle)
    }

    /// The same focal length expressed in view points, for a portrait preview
    /// laid out with `resizeAspectFill`.
    ///
    /// Two transforms sit between the buffer and the screen and both change the
    /// scale, so both have to be undone here.
    ///
    /// First the quarter turn. The app is portrait only and the preview layer
    /// rotates the landscape buffer by ninety degrees, so the buffer's long
    /// axis runs down the screen and its short axis runs across it.
    ///
    /// Then the fill. `resizeAspectFill` scales the rotated image by whichever
    /// factor is larger, so that neither axis leaves a gap, and crops the
    /// surplus off the other one. That single factor converts buffer pixels to
    /// view points, and because pixels are square one focal length serves both
    /// screen axes.
    func focalLengthPoints(displayedIn size: CGSize) -> Double {
        guard size.width > 0, size.height > 0 else { return focalLengthPixels }
        let rotatedWidth = bufferHeight
        let rotatedHeight = bufferWidth
        guard rotatedWidth > 0, rotatedHeight > 0 else { return focalLengthPixels }
        let fill = max(size.width / rotatedWidth, size.height / rotatedHeight)
        return focalLengthPixels * fill
    }
}

// MARK: - The feed

/// The camera, its permission, and its optics.
///
/// Deliberately not ARKit. World tracking buys this app nothing: the sun is at
/// infinity, so its place on the screen depends on which way the phone points
/// and on nothing else, and every device that can run the app has a compass and
/// a gyroscope. ARKit would cost device support, a heavier review surface, and
/// a second permission, in exchange for a plane detector nobody here asked for.
@Observable
final class CameraFeed {

    private(set) var access: CameraAccess = .undetermined
    private(set) var optics: CameraOptics = .assumed
    private(set) var isRunning: Bool = false

    /// Handed to the preview layer. Never touched from the main thread once it
    /// is configured, because starting a session blocks for long enough to drop
    /// frames on the way in.
    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "sunlit.camera.session")
    /// Touched only on `queue`.
    private var isConfigured = false

    init() {
        refreshAccess()
        readOpticsFromDefaultDevice()
    }

    deinit {
        let session = session
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: Permission

    /// Reads the current authorisation without asking for anything.
    func refreshAccess() {
        guard hasBackCamera else {
            access = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: access = .authorised
        case .notDetermined: access = .undetermined
        case .denied: access = .denied
        case .restricted: access = .restricted
        @unknown default: access = .denied
        }
    }

    /// Asks, once, and starts the session if the answer is yes.
    ///
    /// Called from the view's appearance rather than from the initialiser, so
    /// that the permission sheet arrives when the user has opened the camera
    /// view and can see what it is for.
    func requestAccess() {
        refreshAccess()
        switch access {
        case .authorised:
            start()
        case .undetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.access = granted ? .authorised : .denied
                    if granted { self.start() }
                }
            }
        case .denied, .restricted, .unavailable:
            break
        }
    }

    private var hasBackCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    // MARK: Running

    func start() {
        guard access.allowsCapture else { return }
        queue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                self.configure()
            }
            guard self.isConfigured else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            let running = self.session.isRunning
            Task { @MainActor [weak self] in
                self?.isRunning = running
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            Task { @MainActor [weak self] in
                self?.isRunning = false
            }
        }
    }

    /// One input, no output.
    ///
    /// The app never reads a frame. It shows the image and draws over it, so
    /// there is nothing to attach a data output to, and not attaching one is
    /// also the honest answer to the privacy questionnaire: no pixel this
    /// camera produces is ever read by any code in this app.
    private func configure() {
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back) else { return }
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }
        if session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()

        // Read the format after the preset has been committed, not before. The
        // preset is what selects the active format, and the format is what
        // carries the field of view, so a value read first describes a format
        // the session is no longer running.
        let measured = Self.optics(of: device.activeFormat)
        isConfigured = true
        Task { @MainActor [weak self] in
            self?.optics = measured
        }
    }

    /// The optics of whatever format the device would use, read without opening
    /// the session.
    ///
    /// Device properties are readable without camera permission, so even the
    /// refused and restricted screens draw their overlay at the right scale on
    /// hardware that has a camera.
    private func readOpticsFromDefaultDevice() {
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back) else { return }
        optics = Self.optics(of: device.activeFormat)
    }

    private static func optics(of format: AVCaptureDevice.Format) -> CameraOptics {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let fieldOfView = Double(format.videoFieldOfView)
        guard fieldOfView > 0, dimensions.width > 0, dimensions.height > 0 else {
            return .assumed
        }
        return CameraOptics(
            fieldOfViewDegrees: fieldOfView,
            bufferWidth: Double(dimensions.width),
            bufferHeight: Double(dimensions.height),
            isMeasured: true)
    }
}

// MARK: - The preview

/// The live image, and nothing else.
///
/// A layer backed view rather than a hosted `AVCaptureVideoPreviewLayer` added
/// as a sublayer, so the layer resizes with the view instead of needing its
/// frame kept in step by hand. A preview layer whose frame lags the view by one
/// layout pass is the classic source of an overlay that sits a few points off
/// the image it is drawn over.
struct CameraPreview: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .clear
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.isAccessibilityElement = false
        applyPortraitRotation(to: view)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
        }
        // The connection does not exist until the session has an input, which
        // happens after the view is made, so the rotation is applied again on
        // every update until it takes.
        applyPortraitRotation(to: view)
    }

    /// Portrait, always.
    ///
    /// The app is portrait only, and the projection in `SkyOverlay` assumes the
    /// buffer arrives turned a quarter turn. Ninety degrees is the portrait
    /// value of `videoRotationAngle`, which replaced `videoOrientation` in
    /// iOS 17.
    private func applyPortraitRotation(to view: PreviewView) {
        guard let connection = view.previewLayer.connection else { return }
        guard connection.isVideoRotationAngleSupported(90) else { return }
        if connection.videoRotationAngle != 90 {
            connection.videoRotationAngle = 90
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            // Safe by construction: `layerClass` above is what builds it.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
