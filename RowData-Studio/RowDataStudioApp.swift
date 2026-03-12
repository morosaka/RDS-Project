//
//  RowDataStudioApp.swift
//  RowData-Studio
//
//  Created by Mauro M. Sacca on 09/03/26.
//

import AppKit
import SwiftUI
import RowDataStudio

// Classe per gestire eventi di basso livello di macOS se necessario
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        // Set minimum window size
        if let window = NSApp.windows.first {
            window.minSize = NSSize(width: 1024, height: 768)
            window.backgroundColor = .black
        }
    }
}

@main
struct RowDataStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            SessionListView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // Add keyboard commands here (e.g., Spacebar for Play/Pause)
        }
    }
}
