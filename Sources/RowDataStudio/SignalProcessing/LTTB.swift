// SignalProcessing/LTTB.swift v1.0.0
/**
 * Largest Triangle Three Buckets (LTTB) downsampling.
 * Preserves visual features while reducing point count for chart rendering.
 * Reference: Steinarsson (2013), "Downsampling Time Series for Visual Representation."
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Foundation

extension DSP {

    /// Largest Triangle Three Buckets (LTTB) downsampling.
    ///
    /// Selects points that maximize the triangle area with adjacent selected points,
    /// preserving visual features (peaks, valleys, sharp transitions).
    /// Endpoints are always preserved.
    ///
    /// - Parameters:
    ///   - timestamps: Time values (Double for precision).
    ///   - values: Signal values (same length as timestamps).
    ///   - targetCount: Desired number of output points. Must be >= 2.
    /// - Returns: Indices of selected points in the original arrays.
    public static func lttbDownsample(
        timestamps: ContiguousArray<Double>,
        values: ContiguousArray<Float>,
        targetCount: Int
    ) -> [Int] {
        let n = timestamps.count
        guard n == values.count, n > 0 else { return [] }
        guard targetCount >= 2 else { return targetCount == 1 ? [0] : [] }
        guard targetCount < n else { return Array(0..<n) }

        var selectedIndices = [Int]()
        selectedIndices.reserveCapacity(targetCount)

        // Always include first point
        selectedIndices.append(0)

        let bucketSize = Double(n - 2) / Double(targetCount - 2)
        var prevSelectedIdx = 0

        for bucket in 0..<(targetCount - 2) {
            // Current bucket range
            let bucketStart = Int(floor(Double(bucket) * bucketSize)) + 1
            let bucketEnd = min(Int(floor(Double(bucket + 1) * bucketSize)) + 1, n - 1)

            // Next bucket range (for averaging)
            let nextBucketStart = bucketEnd
            let nextBucketEnd = min(
                Int(floor(Double(bucket + 2) * bucketSize)) + 1,
                n
            )

            // Compute average point of next bucket
            var avgX: Double = 0
            var avgY: Double = 0
            let nextBucketLen = nextBucketEnd - nextBucketStart
            if nextBucketLen > 0 {
                for i in nextBucketStart..<nextBucketEnd {
                    avgX += timestamps[i]
                    avgY += Double(values[i])
                }
                avgX /= Double(nextBucketLen)
                avgY /= Double(nextBucketLen)
            }

            // Previous selected point
            let prevX = timestamps[prevSelectedIdx]
            let prevY = Double(values[prevSelectedIdx])

            // Find point in current bucket that maximizes triangle area
            var maxArea: Double = -1
            var bestIdx = bucketStart

            for i in bucketStart..<bucketEnd {
                // Triangle area = 0.5 * |cross product of two edge vectors|
                // = 0.5 * |(xB - xA)(yC - yA) - (xC - xA)(yB - yA)|
                let xB = timestamps[i]
                let yB = Double(values[i])
                let area = abs(
                    (xB - prevX) * (avgY - prevY) -
                    (avgX - prevX) * (yB - prevY)
                ) * 0.5

                if area > maxArea {
                    maxArea = area
                    bestIdx = i
                }
            }

            selectedIndices.append(bestIdx)
            prevSelectedIdx = bestIdx
        }

        // Always include last point
        selectedIndices.append(n - 1)

        return selectedIndices
    }
}
