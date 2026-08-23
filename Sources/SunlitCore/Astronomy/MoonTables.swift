import Foundation

// The two tables below are the periodic terms of Jean Meeus, "Astronomical
// Algorithms", 2nd edition, chapter 47, table 47.A (pages 339 to 340) and
// table 47.B (page 341).
//
// The digits were not typed from memory. They were taken from three published
// reproductions that each cite chapter 47, and the three were diffed against
// one another before transcription:
//
//   PyMeeus, pymeeus/Moon.py, PERIODIC_TERMS_LR_TABLE and
//     PERIODIC_TERMS_B_TABLE (github.com/architest/pymeeus)
//   astronomia, src/moonposition.js, tables ta and tb
//     (github.com/commenthol/astronomia)
//   MeeusJs, lib/Astro.Moon.js, tables ta and tb (github.com/Fabiz/MeeusJs)
//
// All three agree on all 60 rows of each table, digit for digit. As a second,
// independent check the tables were run through Meeus's own worked example
// 47.a (1992 April 12.0 TD) and reproduce his published intermediate sums
// exactly: Sigma l = -1127527, Sigma b = -3229126, Sigma r = -16590875, giving
// longitude 133.162655 degrees, latitude -3.229126 degrees and distance
// 368409.7 km, which match the book to its last printed digit.

/// The periodic terms for the Moon's position, Meeus chapter 47.
///
/// Two things about these tables are easy to get wrong and are not visible in
/// the numbers themselves.
///
/// First, the tables are not the whole series. Meeus adds several terms that
/// are not arguments of D, M, M' and F: the additive terms in A1, A2, A3 and
/// in L' that follow each table in the book. Those belong to the caller, not
/// here.
///
/// Second, every row whose M multiplier is plus or minus 1 must be multiplied
/// by the eccentricity factor E, and every row whose M multiplier is plus or
/// minus 2 by E squared, because the Earth's orbital eccentricity is slowly
/// decreasing and those terms depend on it. Summing the rows as published,
/// without that factor, is wrong by roughly an arcsecond and the error grows
/// with distance from J2000.
public enum MoonTables {

    /// Table 47.A. Each row is the multipliers of D, M, M', F followed by
    /// the coefficient of the sine term for longitude (Sigma l, in units of
    /// 1e-6 degrees) and the coefficient of the cosine term for distance
    /// (Sigma r, in units of 1e-3 km).
    ///
    /// A zero coefficient is a real row of the published table, not padding:
    /// Meeus leaves the Sigma r column blank for terms that do not contribute
    /// to distance, and the final row has no longitude term at all. They are
    /// kept so the array can be checked against the printed page row by row.
    public static let longitudeAndDistance: [(d: Int, m: Int, mPrime: Int, f: Int, l: Double, r: Double)] = [
        (d:  0, m:  0, mPrime:  1, f:  0, l: 6288774, r: -20905355),
        (d:  2, m:  0, mPrime: -1, f:  0, l: 1274027, r:  -3699111),
        (d:  2, m:  0, mPrime:  0, f:  0, l:  658314, r:  -2955968),
        (d:  0, m:  0, mPrime:  2, f:  0, l:  213618, r:   -569925),
        (d:  0, m:  1, mPrime:  0, f:  0, l: -185116, r:     48888),
        (d:  0, m:  0, mPrime:  0, f:  2, l: -114332, r:     -3149),
        (d:  2, m:  0, mPrime: -2, f:  0, l:   58793, r:    246158),
        (d:  2, m: -1, mPrime: -1, f:  0, l:   57066, r:   -152138),
        (d:  2, m:  0, mPrime:  1, f:  0, l:   53322, r:   -170733),
        (d:  2, m: -1, mPrime:  0, f:  0, l:   45758, r:   -204586),
        (d:  0, m:  1, mPrime: -1, f:  0, l:  -40923, r:   -129620),
        (d:  1, m:  0, mPrime:  0, f:  0, l:  -34720, r:    108743),
        (d:  0, m:  1, mPrime:  1, f:  0, l:  -30383, r:    104755),
        (d:  2, m:  0, mPrime:  0, f: -2, l:   15327, r:     10321),
        (d:  0, m:  0, mPrime:  1, f:  2, l:  -12528, r:         0),
        (d:  0, m:  0, mPrime:  1, f: -2, l:   10980, r:     79661),
        (d:  4, m:  0, mPrime: -1, f:  0, l:   10675, r:    -34782),
        (d:  0, m:  0, mPrime:  3, f:  0, l:   10034, r:    -23210),
        (d:  4, m:  0, mPrime: -2, f:  0, l:    8548, r:    -21636),
        (d:  2, m:  1, mPrime: -1, f:  0, l:   -7888, r:     24208),
        (d:  2, m:  1, mPrime:  0, f:  0, l:   -6766, r:     30824),
        (d:  1, m:  0, mPrime: -1, f:  0, l:   -5163, r:     -8379),
        (d:  1, m:  1, mPrime:  0, f:  0, l:    4987, r:    -16675),
        (d:  2, m: -1, mPrime:  1, f:  0, l:    4036, r:    -12831),
        (d:  2, m:  0, mPrime:  2, f:  0, l:    3994, r:    -10445),
        (d:  4, m:  0, mPrime:  0, f:  0, l:    3861, r:    -11650),
        (d:  2, m:  0, mPrime: -3, f:  0, l:    3665, r:     14403),
        (d:  0, m:  1, mPrime: -2, f:  0, l:   -2689, r:     -7003),
        (d:  2, m:  0, mPrime: -1, f:  2, l:   -2602, r:         0),
        (d:  2, m: -1, mPrime: -2, f:  0, l:    2390, r:     10056),
        (d:  1, m:  0, mPrime:  1, f:  0, l:   -2348, r:      6322),
        (d:  2, m: -2, mPrime:  0, f:  0, l:    2236, r:     -9884),
        (d:  0, m:  1, mPrime:  2, f:  0, l:   -2120, r:      5751),
        (d:  0, m:  2, mPrime:  0, f:  0, l:   -2069, r:         0),
        (d:  2, m: -2, mPrime: -1, f:  0, l:    2048, r:     -4950),
        (d:  2, m:  0, mPrime:  1, f: -2, l:   -1773, r:      4130),
        (d:  2, m:  0, mPrime:  0, f:  2, l:   -1595, r:         0),
        (d:  4, m: -1, mPrime: -1, f:  0, l:    1215, r:     -3958),
        (d:  0, m:  0, mPrime:  2, f:  2, l:   -1110, r:         0),
        (d:  3, m:  0, mPrime: -1, f:  0, l:    -892, r:      3258),
        (d:  2, m:  1, mPrime:  1, f:  0, l:    -810, r:      2616),
        (d:  4, m: -1, mPrime: -2, f:  0, l:     759, r:     -1897),
        (d:  0, m:  2, mPrime: -1, f:  0, l:    -713, r:     -2117),
        (d:  2, m:  2, mPrime: -1, f:  0, l:    -700, r:      2354),
        (d:  2, m:  1, mPrime: -2, f:  0, l:     691, r:         0),
        (d:  2, m: -1, mPrime:  0, f: -2, l:     596, r:         0),
        (d:  4, m:  0, mPrime:  1, f:  0, l:     549, r:     -1423),
        (d:  0, m:  0, mPrime:  4, f:  0, l:     537, r:     -1117),
        (d:  4, m: -1, mPrime:  0, f:  0, l:     520, r:     -1571),
        (d:  1, m:  0, mPrime: -2, f:  0, l:    -487, r:     -1739),
        (d:  2, m:  1, mPrime:  0, f: -2, l:    -399, r:         0),
        (d:  0, m:  0, mPrime:  2, f: -2, l:    -381, r:     -4421),
        (d:  1, m:  1, mPrime:  1, f:  0, l:     351, r:         0),
        (d:  3, m:  0, mPrime: -2, f:  0, l:    -340, r:         0),
        (d:  4, m:  0, mPrime: -3, f:  0, l:     330, r:         0),
        (d:  2, m: -1, mPrime:  2, f:  0, l:     327, r:         0),
        (d:  0, m:  2, mPrime:  1, f:  0, l:    -323, r:      1165),
        (d:  1, m:  1, mPrime: -1, f:  0, l:     299, r:         0),
        (d:  2, m:  0, mPrime:  3, f:  0, l:     294, r:         0),
        (d:  2, m:  0, mPrime: -1, f: -2, l:       0, r:      8752),
    ]

    /// Table 47.B. Each row is the multipliers of D, M, M', F followed by
    /// the coefficient of the sine term for latitude (Sigma b, in units of
    /// 1e-6 degrees).
    public static let latitude: [(d: Int, m: Int, mPrime: Int, f: Int, b: Double)] = [
        (d:  0, m:  0, mPrime:  0, f:  1, b: 5128122),
        (d:  0, m:  0, mPrime:  1, f:  1, b:  280602),
        (d:  0, m:  0, mPrime:  1, f: -1, b:  277693),
        (d:  2, m:  0, mPrime:  0, f: -1, b:  173237),
        (d:  2, m:  0, mPrime: -1, f:  1, b:   55413),
        (d:  2, m:  0, mPrime: -1, f: -1, b:   46271),
        (d:  2, m:  0, mPrime:  0, f:  1, b:   32573),
        (d:  0, m:  0, mPrime:  2, f:  1, b:   17198),
        (d:  2, m:  0, mPrime:  1, f: -1, b:    9266),
        (d:  0, m:  0, mPrime:  2, f: -1, b:    8822),
        (d:  2, m: -1, mPrime:  0, f: -1, b:    8216),
        (d:  2, m:  0, mPrime: -2, f: -1, b:    4324),
        (d:  2, m:  0, mPrime:  1, f:  1, b:    4200),
        (d:  2, m:  1, mPrime:  0, f: -1, b:   -3359),
        (d:  2, m: -1, mPrime: -1, f:  1, b:    2463),
        (d:  2, m: -1, mPrime:  0, f:  1, b:    2211),
        (d:  2, m: -1, mPrime: -1, f: -1, b:    2065),
        (d:  0, m:  1, mPrime: -1, f: -1, b:   -1870),
        (d:  4, m:  0, mPrime: -1, f: -1, b:    1828),
        (d:  0, m:  1, mPrime:  0, f:  1, b:   -1794),
        (d:  0, m:  0, mPrime:  0, f:  3, b:   -1749),
        (d:  0, m:  1, mPrime: -1, f:  1, b:   -1565),
        (d:  1, m:  0, mPrime:  0, f:  1, b:   -1491),
        (d:  0, m:  1, mPrime:  1, f:  1, b:   -1475),
        (d:  0, m:  1, mPrime:  1, f: -1, b:   -1410),
        (d:  0, m:  1, mPrime:  0, f: -1, b:   -1344),
        (d:  1, m:  0, mPrime:  0, f: -1, b:   -1335),
        (d:  0, m:  0, mPrime:  3, f:  1, b:    1107),
        (d:  4, m:  0, mPrime:  0, f: -1, b:    1021),
        (d:  4, m:  0, mPrime: -1, f:  1, b:     833),
        (d:  0, m:  0, mPrime:  1, f: -3, b:     777),
        (d:  4, m:  0, mPrime: -2, f:  1, b:     671),
        (d:  2, m:  0, mPrime:  0, f: -3, b:     607),
        (d:  2, m:  0, mPrime:  2, f: -1, b:     596),
        (d:  2, m: -1, mPrime:  1, f: -1, b:     491),
        (d:  2, m:  0, mPrime: -2, f:  1, b:    -451),
        (d:  0, m:  0, mPrime:  3, f: -1, b:     439),
        (d:  2, m:  0, mPrime:  2, f:  1, b:     422),
        (d:  2, m:  0, mPrime: -3, f: -1, b:     421),
        (d:  2, m:  1, mPrime: -1, f:  1, b:    -366),
        (d:  2, m:  1, mPrime:  0, f:  1, b:    -351),
        (d:  4, m:  0, mPrime:  0, f:  1, b:     331),
        (d:  2, m: -1, mPrime:  1, f:  1, b:     315),
        (d:  2, m: -2, mPrime:  0, f: -1, b:     302),
        (d:  0, m:  0, mPrime:  1, f:  3, b:    -283),
        (d:  2, m:  1, mPrime:  1, f: -1, b:    -229),
        (d:  1, m:  1, mPrime:  0, f: -1, b:     223),
        (d:  1, m:  1, mPrime:  0, f:  1, b:     223),
        (d:  0, m:  1, mPrime: -2, f: -1, b:    -220),
        (d:  2, m:  1, mPrime: -1, f: -1, b:    -220),
        (d:  1, m:  0, mPrime:  1, f:  1, b:    -185),
        (d:  2, m: -1, mPrime: -2, f: -1, b:     181),
        (d:  0, m:  1, mPrime:  2, f:  1, b:    -177),
        (d:  4, m:  0, mPrime: -2, f: -1, b:     176),
        (d:  4, m: -1, mPrime: -1, f: -1, b:     166),
        (d:  1, m:  0, mPrime:  1, f: -1, b:    -164),
        (d:  4, m:  0, mPrime:  1, f: -1, b:     132),
        (d:  1, m:  0, mPrime: -1, f: -1, b:    -119),
        (d:  4, m: -1, mPrime:  0, f: -1, b:     115),
        (d:  2, m: -2, mPrime:  0, f:  1, b:     107),
    ]
}
