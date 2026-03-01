// RowDataStudio/ContentView.swift v0.1.0
/**
 * Root content view for RowData Studio.
 * --- Revision History ---
 * v0.1.0 - 2026-03-01 - ARCHITECTURE: Initial scaffold.
 */

import SwiftUI

/// Placeholder root view. Will be replaced by the session list / analysis canvas.
public struct ContentView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Text("RowData Studio")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Rowing Performance Analysis")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("v0.1.0 — Phase 0 Scaffold")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
