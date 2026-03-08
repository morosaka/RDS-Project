// RowDataStudioApp/App.swift v0.4.0
/**
 * Main application entry point for RowData Studio.
 * --- Revision History ---
 * v0.4.0 - 2026-03-08 - Xcode project migration: remove 'import RowDataStudio' (files now in target directly).
 * v0.3.0 - 2026-03-08 - AppDelegate for robust SPM focus (NSApp.activate at launch).
 * v0.2.0 - 2026-03-08 - Root view → SessionListView (Phase 6-7 testing).
 * v0.1.0 - 2026-03-01 - ARCHITECTURE: Initial scaffold.
 */

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Not needed with a real bundle ID, but harmless.
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct RowDataStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            SessionListView()
        }
        .commands {
            // Disable default "New Window" from Cmd+N (not needed for document app)
        }
    }
}
