import Foundation
import CoreLocation
import CoreMotion
import Observation

/// Where the device is pointing, and how much that answer can be trusted.
///
/// The single most cited weakness of the app this one competes with is compass
/// accuracy, and it lands on its augmented reality view, which is its hero
/// feature. Two decisions here address that.
///
/// First, the heading does not come from the magnetometer alone. It comes from
/// CoreMotion's sensor fusion in the true north reference frame, which blends
/// the gyroscope with the magnetometer and is markedly steadier than raw
/// magnetic heading. The location manager still runs, because the true north
/// frame needs it and because it is the only source of a calibration signal.
///
/// Second, the uncertainty is shown rather than hidden. A number with a stated
/// error is an instrument. A number without one is a guess wearing a uniform.
@Observable
final class HeadingProvider: NSObject {

    /// Degrees from true north, increasing toward east.
    private(set) var trueHeading: Double = 0
    /// The device's own estimate of its error, in degrees. Negative means the
    /// heading is not valid at all.
    private(set) var accuracyDegrees: Double = -1
    /// Pitch: how far the device is tilted up from horizontal, in degrees.
    /// Positive when the top of the phone points at the sky.
    private(set) var pitchDegrees: Double = 0
    /// Roll about the device's long axis, in degrees.
    private(set) var rollDegrees: Double = 0
    private(set) var isRunning: Bool = false

    /// How the interface should present the current uncertainty.
    enum Quality {
        case unavailable
        case poor
        case fair
        case good

        var needsCalibration: Bool { self == .poor || self == .unavailable }
    }

    var quality: Quality {
        guard accuracyDegrees >= 0 else { return .unavailable }
        switch accuracyDegrees {
        case ..<8: return .good
        case ..<20: return .fair
        default: return .poor
        }
    }

    private let motion = CMMotionManager()
    private let location = CLLocationManager()
    private let queue = OperationQueue()

    override init() {
        super.init()
        location.delegate = self
        queue.name = "sunlit.heading"
        queue.maxConcurrentOperationCount = 1
    }

    /// Screenshot capture only. A simulator has no magnetometer and no camera, so
    /// the AR view honestly reports "no compass" and draws almost nothing, which
    /// is correct on a device that cannot point but makes the store screenshot a
    /// picture of a warning. Fixing a heading and a pitch shows the real
    /// projection, computed by the same code, from a stated viewpoint.
    #if DEBUG
    func useFixedAim(heading: Double, pitch: Double, accuracy: Double = 3) {
        stop()
        trueHeading = heading
        pitchDegrees = pitch
        rollDegrees = 0
        accuracyDegrees = accuracy
        isFixed = true
    }
    private var isFixed = false
    #endif

    func start() {
        #if DEBUG
        if isFixed { return }
        #endif
        guard !isRunning else { return }
        guard motion.isDeviceMotionAvailable else {
            accuracyDegrees = -1
            return
        }
        isRunning = true

        // The heading updates carry the accuracy figure, which device motion
        // does not expose. They are also what prompts the system calibration
        // sheet when the field is disturbed.
        if CLLocationManager.headingAvailable() {
            location.headingFilter = 0.2
            location.startUpdatingHeading()
        }

        // Twenty hertz. The augmented reality overlay is redrawn at display
        // rate, but the attitude itself does not need to be sampled faster than
        // the eye can follow, and halving the rate halves the battery cost of a
        // view people hold up for minutes at a time.
        motion.deviceMotionUpdateInterval = 1.0 / 20.0
        motion.startDeviceMotionUpdates(
            using: .xTrueNorthZVertical,
            to: queue
        ) { [weak self] deviceMotion, _ in
            guard let self, let deviceMotion else { return }
            let attitude = deviceMotion.attitude

            // In the true north frame the yaw is measured from north, but it
            // runs counterclockwise and starts along the device's x axis, so it
            // needs both a sign flip and a quarter turn to become a compass
            // bearing. Getting either wrong puts the sun on the opposite side
            // of the sky, which is exactly the class of bug this app exists to
            // avoid.
            let yawDegrees = -attitude.yaw * 180.0 / .pi
            let bearing = (yawDegrees + 90.0).truncatingRemainder(dividingBy: 360.0)

            let pitch = attitude.pitch * 180.0 / .pi
            let roll = attitude.roll * 180.0 / .pi

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.trueHeading = bearing < 0 ? bearing + 360 : bearing
                self.pitchDegrees = pitch
                self.rollDegrees = roll
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        motion.stopDeviceMotionUpdates()
        location.stopUpdatingHeading()
    }
}

extension HeadingProvider: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        accuracyDegrees = newHeading.headingAccuracy
    }

    /// Returning true lets the system put up its own calibration sheet, which
    /// is the only reliable way to get a user to wave the phone in a figure of
    /// eight. It is suppressed once the reading is good so it does not nag.
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        quality.needsCalibration
    }
}
