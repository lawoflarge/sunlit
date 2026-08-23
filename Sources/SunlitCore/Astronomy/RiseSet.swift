import Foundation

/// Finds the instants at which a body crosses a given altitude.
///
/// Meeus gives an interpolation method for rise and set that assumes the body
/// moves smoothly across a single day and that a crossing exists. Both
/// assumptions break where this app has to be right: above the Arctic Circle the
/// crossing may not exist at all, near it the body grazes the horizon and the
/// interpolation picks the wrong root, and the Moon moves fast enough that its
/// own target altitude changes measurably during the day it is being solved for.
///
/// This solver samples instead. It costs about 1440 ephemeris evaluations per
/// day, which at four microseconds each is six milliseconds, and in exchange it
/// is correct at the poles, correct for grazing events, correct when the target
/// altitude is itself a function of time, and correct when a body rises twice in
/// one calendar day.
public enum RiseSet {

    public enum Kind: String, Sendable {
        case rise
        case set
    }

    public struct Crossing: Sendable {
        public let julianDay: JulianDay
        public let kind: Kind
    }

    /// What happened over the interval.
    public struct Outcome: Sendable {
        public let crossings: [Crossing]
        /// The instant of greatest altitude, and that altitude.
        public let transit: (julianDay: JulianDay, altitude: Double)?
        /// The instant of least altitude, and that altitude.
        public let antitransit: (julianDay: JulianDay, altitude: Double)?
        /// True when the body never dropped to the target altitude.
        public let alwaysAbove: Bool
        /// True when the body never reached the target altitude.
        public let alwaysBelow: Bool

        public var firstRise: JulianDay? { crossings.first(where: { $0.kind == .rise })?.julianDay }
        public var lastSet: JulianDay? { crossings.last(where: { $0.kind == .set })?.julianDay }
    }

    /// Solves for crossings of `target` by `altitude` over `[start, end]`.
    ///
    /// - Parameters:
    ///   - start: beginning of the interval.
    ///   - end: end of the interval.
    ///   - sampleSeconds: coarse sampling step. Sixty seconds is fine for the
    ///     Sun and the Moon; a faster body would need less.
    ///   - precisionSeconds: how tightly each crossing is bracketed.
    ///   - altitude: the body's altitude at an instant, in degrees.
    ///   - target: the altitude being crossed, at an instant, in degrees. It is
    ///     a function rather than a constant because the Moon's rise altitude
    ///     depends on its parallax, which changes through the day, and because
    ///     a measured horizon profile depends on the azimuth, which changes
    ///     continuously.
    public static func solve(
        start: JulianDay,
        end: JulianDay,
        sampleSeconds: Double = 60,
        precisionSeconds: Double = 1,
        altitude: (JulianDay) -> Double,
        target: (JulianDay) -> Double
    ) -> Outcome {
        let span = end.value - start.value
        guard span > 0 else {
            return Outcome(crossings: [], transit: nil, antitransit: nil,
                           alwaysAbove: false, alwaysBelow: false)
        }

        let step = sampleSeconds / 86400.0
        let count = max(2, Int((span / step).rounded(.up)))

        // f is positive when the body is above the target.
        func f(_ jd: JulianDay) -> Double { altitude(jd) - target(jd) }

        var samples: [(jd: JulianDay, f: Double, altitude: Double)] = []
        samples.reserveCapacity(count + 1)
        for i in 0...count {
            let jd = JulianDay(start.value + span * Double(i) / Double(count))
            let a = altitude(jd)
            samples.append((jd, a - target(jd), a))
        }

        var crossings: [Crossing] = []
        for i in 1..<samples.count {
            let previous = samples[i - 1]
            let current = samples[i]
            guard previous.f.sign != current.f.sign || previous.f == 0 || current.f == 0 else { continue }
            guard previous.f != current.f else { continue }
            let kind: Kind = previous.f < current.f ? .rise : .set
            let root = bisect(low: previous.jd, high: current.jd,
                              precisionSeconds: precisionSeconds, f: f)
            crossings.append(Crossing(julianDay: root, kind: kind))
        }

        // The extremes. A parabola through the three samples around the coarse
        // maximum refines it well below the sampling step, because altitude is
        // smooth and nearly quadratic near its turning point.
        var maxIndex = 0
        var minIndex = 0
        for i in samples.indices {
            if samples[i].altitude > samples[maxIndex].altitude { maxIndex = i }
            if samples[i].altitude < samples[minIndex].altitude { minIndex = i }
        }
        let transit = refineExtreme(samples, around: maxIndex, altitude: altitude)
        let antitransit = refineExtreme(samples, around: minIndex, altitude: altitude)

        let alwaysAbove = crossings.isEmpty && samples.allSatisfy { $0.f > 0 }
        let alwaysBelow = crossings.isEmpty && samples.allSatisfy { $0.f < 0 }

        return Outcome(crossings: crossings, transit: transit, antitransit: antitransit,
                       alwaysAbove: alwaysAbove, alwaysBelow: alwaysBelow)
    }

    private static func bisect(
        low: JulianDay,
        high: JulianDay,
        precisionSeconds: Double,
        f: (JulianDay) -> Double
    ) -> JulianDay {
        var a = low.value
        var b = high.value
        var fa = f(JulianDay(a))
        let tolerance = precisionSeconds / 86400.0

        // A guard on the iteration count as well as on the interval: if the
        // function is pathological the loop still terminates.
        var iterations = 0
        while b - a > tolerance && iterations < 60 {
            let mid = (a + b) / 2.0
            let fm = f(JulianDay(mid))
            if fm == 0 { return JulianDay(mid) }
            if (fa < 0) == (fm < 0) {
                a = mid
                fa = fm
            } else {
                b = mid
            }
            iterations += 1
        }
        return JulianDay((a + b) / 2.0)
    }

    private static func refineExtreme(
        _ samples: [(jd: JulianDay, f: Double, altitude: Double)],
        around index: Int,
        altitude: (JulianDay) -> Double
    ) -> (julianDay: JulianDay, altitude: Double)? {
        guard !samples.isEmpty else { return nil }
        guard index > 0, index < samples.count - 1 else {
            return (samples[index].jd, samples[index].altitude)
        }

        let y0 = samples[index - 1].altitude
        let y1 = samples[index].altitude
        let y2 = samples[index + 1].altitude
        let denominator = y0 - 2 * y1 + y2
        guard abs(denominator) > 1e-12 else {
            return (samples[index].jd, samples[index].altitude)
        }
        // Offset of the parabola's vertex from the middle sample, in units of
        // the sampling step, clamped so a nearly flat curve cannot throw the
        // answer outside the bracket.
        let offset = max(-1, min(1, 0.5 * (y0 - y2) / denominator))
        let stepDays = samples[index].jd.value - samples[index - 1].jd.value
        let jd = JulianDay(samples[index].jd.value + offset * stepDays)
        return (jd, altitude(jd))
    }
}
