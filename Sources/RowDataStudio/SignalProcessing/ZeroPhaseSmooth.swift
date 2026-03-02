// SignalProcessing/ZeroPhaseSmooth.swift v1.0.0
/**
 * Zero-phase smoothing via forward + backward pass.
 * Eliminates phase distortion by applying SMA in both directions.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Foundation

extension DSP {

    /// Applies zero-phase smoothing (forward + backward SMA pass).
    ///
    /// Eliminates phase distortion by applying a simple moving average forward,
    /// then reversing and applying again. Peak positions are preserved.
    /// Used in stroke detection (fusion-engine.md §Step 3).
    ///
    /// - Parameters:
    ///   - signal: Input signal.
    ///   - halfWindowSize: Half the smoothing window. Full window = `2 * halfWindowSize + 1`.
    /// - Returns: Zero-phase smoothed signal of the same length.
    public static func zeroPhaseSmooth(
        _ signal: ContiguousArray<Float>,
        halfWindowSize: Int
    ) -> ContiguousArray<Float> {
        guard signal.count > 1, halfWindowSize > 0 else { return signal }

        let windowSize = 2 * halfWindowSize + 1

        // Forward pass
        let forward = simpleMovingAverage(signal, windowSize: windowSize)

        // Reverse
        let reversed = ContiguousArray<Float>(forward.reversed())

        // Backward pass
        let backward = simpleMovingAverage(reversed, windowSize: windowSize)

        // Reverse again to restore original order
        return ContiguousArray(backward.reversed())
    }
}
