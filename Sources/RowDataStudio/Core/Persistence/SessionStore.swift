// SessionStore.swift v1.0.0
/**
 * JSON-based session persistence layer.
 *
 * Provides CRUD operations for SessionDocument instances, storing them
 * in ~/Library/Application Support/RowDataStudio/sessions/ as JSON files.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 5: Session Management).
 *
 * Source: docs/architecture/data-models.md §SessionDocument
 *
 * CRITICAL: Source files are never modified by SessionStore.
 * SessionDocument contains virtual references only (trim, sync, annotations).
 */

import Foundation

/// Errors that can occur during session store operations.
public enum SessionStoreError: LocalizedError {
    case directoryNotFound
    case directoryCreationFailed(Error)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case sessionNotFound(UUID)
    case fileNotFound(String)
    case deletionFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .directoryNotFound:
            return "Session directory not found and could not be created"
        case .directoryCreationFailed(let error):
            return "Failed to create session directory: \(error.localizedDescription)"
        case .encodingFailed(let error):
            return "Failed to encode session: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode session: \(error.localizedDescription)"
        case .sessionNotFound(let id):
            return "Session not found: \(id.uuidString)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .deletionFailed(let error):
            return "Failed to delete session: \(error.localizedDescription)"
        }
    }
}

/// JSON-based session store.
///
/// Persists SessionDocument instances to disk in `~/Library/Application Support/RowDataStudio/sessions/`.
/// Each session is stored as `{sessionID}.json`.
///
/// Thread-safe using serial DispatchQueue for all I/O operations.
public actor SessionStore {
    private let sessionDirectory: URL
    private let ioQueue = DispatchQueue(label: "com.rowdatastudio.sessionstore.io")

    /// Initialize the session store.
    ///
    /// Creates the session directory if it does not exist.
    /// - Throws: `SessionStoreError.directoryCreationFailed` if directory creation fails
    public init() throws {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.sessionDirectory = appSupport.appendingPathComponent("RowDataStudio", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)

        // Ensure directory exists
        try ioQueue.sync {
            if !fileManager.fileExists(atPath: sessionDirectory.path) {
                do {
                    try fileManager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
                } catch {
                    throw SessionStoreError.directoryCreationFailed(error)
                }
            }
        }
    }

    /// Save a session document to disk.
    ///
    /// Overwrites any existing session with the same ID.
    /// Updates `modifiedAt` to the current date.
    ///
    /// - Parameter document: The session to save
    /// - Throws: `SessionStoreError.encodingFailed` if JSON encoding fails
    public func save(_ document: SessionDocument) async throws {
        var mutableDoc = document
        mutableDoc.modifiedAt = Date()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let fileURL = sessionDirectory.appendingPathComponent(
            document.metadata.id.uuidString,
            isDirectory: false
        ).appendingPathExtension("json")

        do {
            let data = try encoder.encode(mutableDoc)
            try ioQueue.sync {
                try data.write(to: fileURL, options: .atomic)
            }
        } catch {
            throw SessionStoreError.encodingFailed(error)
        }
    }

    /// Load a session document by ID.
    ///
    /// - Parameter id: The session ID to load
    /// - Returns: The decoded SessionDocument
    /// - Throws: `SessionStoreError.sessionNotFound` if no session exists with this ID,
    ///           or `SessionStoreError.decodingFailed` if decoding fails
    public func load(id: UUID) async throws -> SessionDocument {
        let fileURL = sessionDirectory.appendingPathComponent(
            id.uuidString,
            isDirectory: false
        ).appendingPathExtension("json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SessionStoreError.sessionNotFound(id)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try ioQueue.sync {
                try Data(contentsOf: fileURL)
            }
            return try decoder.decode(SessionDocument.self, from: data)
        } catch let decodingError as DecodingError {
            throw SessionStoreError.decodingFailed(decodingError)
        } catch {
            throw SessionStoreError.decodingFailed(error)
        }
    }

    /// List all sessions, sorted by modification date (newest first).
    ///
    /// - Returns: Array of SessionDocument instances
    /// - Throws: `SessionStoreError.decodingFailed` if any session cannot be decoded
    public func listAll() async throws -> [SessionDocument] {
        let fileURLs = try ioQueue.sync {
            try FileManager.default.contentsOfDirectory(
                at: sessionDirectory,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var sessions: [SessionDocument] = []

        for fileURL in fileURLs {
            do {
                let data = try ioQueue.sync {
                    try Data(contentsOf: fileURL)
                }
                let session = try decoder.decode(SessionDocument.self, from: data)
                sessions.append(session)
            } catch {
                throw SessionStoreError.decodingFailed(error)
            }
        }

        // Sort by modification date (newest first)
        return sessions.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Delete a session by ID.
    ///
    /// - Parameter id: The session ID to delete
    /// - Throws: `SessionStoreError.deletionFailed` if file deletion fails
    public func delete(id: UUID) async throws {
        let fileURL = sessionDirectory.appendingPathComponent(
            id.uuidString,
            isDirectory: false
        ).appendingPathExtension("json")

        do {
            try ioQueue.sync {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            throw SessionStoreError.deletionFailed(error)
        }
    }

    /// Check if a session exists.
    ///
    /// - Parameter id: The session ID to check
    /// - Returns: True if the session exists, false otherwise
    public func exists(id: UUID) async -> Bool {
        let fileURL = sessionDirectory.appendingPathComponent(
            id.uuidString,
            isDirectory: false
        ).appendingPathExtension("json")

        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
