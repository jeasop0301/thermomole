import Foundation

/// Pure mapping of a value series onto vertical fractions for a sparkline.
/// Each fraction is 0...1 where 0 is the bottom of the plot and 1 the top.
///
/// A flat series (every value equal) or a single sample maps to a centered 0.5
/// instead of pinning to the bottom edge, so a steady reading still draws a
/// visible horizontal line rather than vanishing against the frame. UI-free and
/// unit-tested.
public enum SparklineScale {
    /// Differences at or below this are treated as flat to avoid amplifying noise.
    public static let flatEpsilon = 0.0001

    public static func fractions(_ values: [Double]) -> [Double] {
        guard let lo = values.min(), let hi = values.max() else { return [] }
        let range = hi - lo
        if range <= flatEpsilon { return values.map { _ in 0.5 } }
        return values.map { ($0 - lo) / range }
    }
}
