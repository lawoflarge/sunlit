import Foundation

/// One local day of the sun, swept once and shared.
///
/// `Twilight.phases`, `GoldenHour.golden` and `GoldenHour.blue` each used to
/// sweep the whole day for themselves at sixty second steps, so building one
/// `DayReport` swept the same day six times over and evaluated the solar
/// position several thousand times for numbers that were already known. This
/// type sweeps it once and hands the sweep to all three.
///
/// The sweep is only ever used to BRACKET. Nothing the interface shows is read
/// off the sampling grid: `crossings` finds the pair of samples a crossing lies
/// between and then bisects with the exact SPA, and `maximum` and `minimum`
/// refine the coarse turning point and then evaluate it. So the step decides
/// only whether an event is found, never how precisely it is placed, and the
/// answers stay as exact as they were at sixty seconds.
///
/// Three hundred seconds is safe for the sun. Its altitude changes by at most
/// fifteen degrees an hour, which is one and a quarter degrees per step, and the
/// thresholds this core solves for are six degrees apart, so no crossing of a
/// threshold can hide between two samples: to be missed the sun would have to
/// cross and come back inside one step, which needs a turning point within a
/// degree and a quarter of the threshold. That is the polar grazing case, it is
/// confined to a few days a year within a few degrees of the Arctic and
/// Antarctic circles, and it was already possible at the sixty second step this
/// replaces. The narrowest band solved here, the two degree blue hour, takes at
/// least four hundred and eighty seconds to cross at any latitude, so it too
/// always contains a sample.
public struct SolarDay: Sendable {

    /// One instant of the sweep.
    public struct Sample: Sendable {
        public let instant: JulianDay
        /// Geometric altitude in degrees, refraction NOT applied. Every
        /// threshold in this core, from the -0.8333 degrees of sunrise to the
        /// -18 of astronomical twilight and the edges of the golden and blue
        /// bands, is defined on the geometric altitude, so this is the one the
        /// solvers compare against.
        public let altitude: Double
        /// Apparent altitude in degrees, refraction applied. This is what the
        /// interface draws and what `Coordinates.Horizontal` carries.
        public let apparentAltitude: Double
        public let azimuth: Double
    }

    /// Start of the local day, expressed in Universal Time.
    public let start: JulianDay
    public let place: Coordinates.Geographic
    public let stepSeconds: Double

    /// The sweep, from `start` to `start` plus one day inclusive.
    public let samples: [Sample]

    /// The instant of greatest geometric altitude in the day, and that
    /// altitude, refined below the sampling step and then evaluated exactly.
    public let maximum: (instant: JulianDay, altitude: Double)
    /// The instant of least geometric altitude, likewise.
    public let minimum: (instant: JulianDay, altitude: Double)

    public init(
        start: JulianDay,
        place: Coordinates.Geographic,
        stepSeconds: Double = 300
    ) {
        self.start = start
        self.place = place
        self.stepSeconds = stepSeconds

        let count = max(2, Int((86400.0 / stepSeconds).rounded()))
        var swept: [Sample] = []
        swept.reserveCapacity(count + 1)
        for i in 0...count {
            let instant = start.adding(seconds: Double(i) * stepSeconds)
            let solar = SolarPositionSPA.evaluate(julianDay: instant, place: place)
            swept.append(Sample(
                instant: instant,
                altitude: solar.elevationWithoutRefraction,
                apparentAltitude: solar.elevation,
                azimuth: solar.azimuth))
        }
        self.samples = swept

        // The turning points are refined by the same parabola `RiseSet` uses,
        // called on the same shape of input, so that a day solved through this
        // type and a day solved through `RiseSet.solve` place transit and
        // antitransit by identical arithmetic.
        let exact = { (jd: JulianDay) -> Double in
            SolarPositionSPA.evaluate(julianDay: jd, place: place).elevationWithoutRefraction
        }
        let forRefinement = swept.map { (jd: $0.instant, f: $0.altitude, altitude: $0.altitude) }
        var high = 0
        var low = 0
        for i in swept.indices {
            if swept[i].altitude > swept[high].altitude { high = i }
            if swept[i].altitude < swept[low].altitude { low = i }
        }
        let peak = RiseSet.refineExtreme(forRefinement, around: high, altitude: exact)
            ?? (swept[high].instant, swept[high].altitude)
        let trough = RiseSet.refineExtreme(forRefinement, around: low, altitude: exact)
            ?? (swept[low].instant, swept[low].altitude)
        self.maximum = (instant: peak.0, altitude: peak.1)
        self.minimum = (instant: trough.0, altitude: trough.1)
    }

    /// The last instant of the sweep, one day after `start`.
    public var end: JulianDay { samples[samples.count - 1].instant }

    /// The sun's geometric altitude at any instant, evaluated exactly. Not a
    /// cache lookup: this is what the bisection calls, and it is the reason a
    /// coarse sweep costs nothing in precision.
    public func altitude(at instant: JulianDay) -> Double {
        SolarPositionSPA.evaluate(julianDay: instant, place: place).elevationWithoutRefraction
    }

    /// The sun's azimuth at any instant, evaluated exactly.
    public func azimuth(at instant: JulianDay) -> Double {
        SolarPositionSPA.evaluate(julianDay: instant, place: place).azimuth
    }

    /// Crossings of a fixed altitude threshold, in degrees.
    public func crossings(
        target: Double,
        precisionSeconds: Double = 1
    ) -> [RiseSet.Crossing] {
        crossings(precisionSeconds: precisionSeconds, of: { $0 - target })
    }

    /// Crossings of zero by any signed function of the sun's geometric
    /// altitude.
    ///
    /// The general form exists for the golden and blue hours, whose edges are a
    /// band rather than a threshold and which turn "between two altitudes" into
    /// a single signed depth so that one solve finds both edges.
    public func crossings(
        precisionSeconds: Double = 1,
        of signal: (Double) -> Double
    ) -> [RiseSet.Crossing] {
        func f(_ jd: JulianDay) -> Double { signal(altitude(at: jd)) }

        var found: [RiseSet.Crossing] = []
        var previous = signal(samples[0].altitude)
        for i in 1..<samples.count {
            let current = signal(samples[i].altitude)
            defer { previous = current }
            guard previous.sign != current.sign || previous == 0 || current == 0 else { continue }
            guard previous != current else { continue }
            let kind: RiseSet.Kind = previous < current ? .rise : .set
            let root = RiseSet.bisect(
                low: samples[i - 1].instant,
                high: samples[i].instant,
                precisionSeconds: precisionSeconds,
                f: f)
            found.append(RiseSet.Crossing(julianDay: root, kind: kind))
        }
        return found
    }
}
