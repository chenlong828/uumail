import AppKit
import Foundation
import MailDomain
import Presentation
import SwiftUI

/// One save destination chosen by the user. Injected so the save flow is testable without
/// opening a real `NSSavePanel` (REQ-0026 / SCN-0020).
@MainActor
protocol SavePanelPresenting {
    /// `nil` means the user cancelled the panel.
    func destination(for suggestedName: String) -> URL?
}

@MainActor
struct SystemSavePanel: SavePanelPresenting {
    func destination(for suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Copies a cached attachment to a user-chosen destination without occupying the main
/// thread: chunked I/O runs on a detached task, cancellation is forwarded to it, and the
/// destination is only touched after the copy is complete.
enum AttachmentFileCopy {
    nonisolated static func copy(from source: URL, to destination: URL) async throws {
        if source.standardizedFileURL == destination.standardizedFileURL { return }
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw MailError.storage(reason: "附件缓存文件不存在")
        }
        let worker = Task.detached(priority: .userInitiated) {
            try copyChunked(from: source, to: destination)
        }
        try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Temporary file in the destination directory, 1 MiB chunks, a cancellation check per
    /// chunk, then an atomic move (new target) or replace (existing target).
    nonisolated private static func copyChunked(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        let directory = destination.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(
            ".\(destination.lastPathComponent).uumail-tmp-\(UUID().uuidString)"
        )
        var installed = false

        let input: FileHandle
        do {
            input = try FileHandle(forReadingFrom: source)
        } catch {
            throw MailError.storage(reason: error.localizedDescription)
        }
        defer { try? input.close() }

        guard manager.createFile(atPath: temporary.path, contents: nil) else {
            throw MailError.storage(reason: "无法创建临时文件")
        }
        let output: FileHandle
        do {
            output = try FileHandle(forWritingTo: temporary)
        } catch {
            try? manager.removeItem(at: temporary)
            throw MailError.storage(reason: error.localizedDescription)
        }
        var outputOpen = true
        defer {
            if outputOpen { try? output.close() }
            if !installed { try? manager.removeItem(at: temporary) }
        }

        do {
            while true {
                try Task.checkCancellation()
                guard let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty else { break }
                try output.write(contentsOf: chunk)
            }
            try output.synchronize()
            try output.close()
            outputOpen = false
            try input.close()

            if manager.fileExists(atPath: destination.path) {
                _ = try manager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: destination)
            }
            installed = true
        } catch {
            if error is CancellationError { throw error }
            if let mailError = error as? MailError { throw mailError }
            throw MailError.storage(reason: error.localizedDescription)
        }
    }
}

/// Panel → copy → result text. It never downloads: a missing source is reported as a
/// retryable text instead of silently re-resolving it against a newer selection (D16).
@MainActor
struct AttachmentSaveFlow {
    /// The source was pruned after the download returned; retry by choosing 另存为… again.
    static let missingSourceText = "附件缓存已失效，请重试另存为"

    let panel: any SavePanelPresenting
    let copy: @Sendable (URL, URL) async throws -> Void
    let fileExists: @MainActor (URL) -> Bool

    /// `nil` = success or a user cancel; a Chinese text = a visible failure.
    func run(
        source: URL,
        displayName: String,
        shouldContinue: @MainActor () -> Bool
    ) async -> String? {
        guard !Task.isCancelled else { return nil }
        guard fileExists(source) else { return Self.missingSourceText }
        guard let destination = panel.destination(for: displayName) else { return nil }
        guard !Task.isCancelled, shouldContinue() else { return nil }
        do {
            try await copy(source, destination)
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            if !fileExists(source) { return Self.missingSourceText }
            let normalized = (error as? MailError) ?? .storage(reason: String(describing: error))
            return ErrorText.text(for: normalized)
        }
    }
}

/// Per-attachment single-flight for one action kind: a second click returns before starting
/// a second open/save. It does not replace the origin guard; it only drops duplicates.
@MainActor
final class AttachmentActionGate {
    private var active: Set<String> = []

    func begin(_ id: String) -> Bool {
        guard !active.contains(id) else { return false }
        active.insert(id)
        return true
    }

    func end(_ id: String) {
        active.remove(id)
    }
}

/// App-level coordinator for one open/save action. It owns the action epoch, the save state
/// and the save task; it never downloads or touches files itself. Every await is followed by
/// an `isCurrent` check so a result from another selection (including A→B→A) is dropped
/// (REQ-0026 / SCN-0020; design3 §4.2.2).
@MainActor
@Observable
final class AttachmentActionModel {
    struct Origin: Equatable {
        let key: String?
        let epoch: UInt64
    }

    private(set) var epoch: UInt64 = 0
    private(set) var saveErrorText: String?
    private var saving: (id: String, origin: Origin)?
    private var observedKey: String?
    private var saveTask: Task<Void, Never>?
    private let openGate = AttachmentActionGate()
    private let saveGate = AttachmentActionGate()

    private let currentKey: @MainActor () -> String?
    private let download: @MainActor (Attachment) async -> URL?
    private let panel: any SavePanelPresenting
    private let copy: @Sendable (URL, URL) async throws -> Void
    private let openFile: @MainActor (URL) -> Bool
    private let fileExists: @MainActor (URL) -> Bool

    init(
        currentKey: @MainActor @escaping () -> String?,
        download: @MainActor @escaping (Attachment) async -> URL?,
        panel: (any SavePanelPresenting)? = nil,
        copy: @Sendable @escaping (URL, URL) async throws -> Void = { source, destination in
            try await AttachmentFileCopy.copy(from: source, to: destination)
        },
        openFile: @MainActor @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        fileExists: @MainActor @escaping (URL) -> Bool = {
            FileManager.default.fileExists(atPath: $0.path)
        }
    ) {
        self.currentKey = currentKey
        self.download = download
        self.panel = panel ?? SystemSavePanel()
        self.copy = copy
        self.openFile = openFile
        self.fileExists = fileExists
        self.observedKey = currentKey()
    }

    /// Non-nil only while the panel/copy stage of the current selection is running.
    var visibleSavingID: String? {
        guard let saving, isCurrent(saving.origin) else { return nil }
        return saving.id
    }

    /// The only place `epoch` changes. Both the list binding setter and the `.onChange`
    /// fallback call it; the `observedKey` short-circuit keeps one change from counting twice.
    func syncSelection() {
        let key = currentKey()
        guard key != observedKey else { return }
        observedKey = key
        epoch &+= 1
        saveErrorText = nil
        if let saving, !isCurrent(saving.origin) { self.saving = nil }
    }

    func open(_ attachment: Attachment) async {
        guard openGate.begin(attachment.id) else { return }
        defer { openGate.end(attachment.id) }
        let origin = origin()
        saveErrorText = nil
        guard var url = await download(attachment), isCurrent(origin) else { return }
        if !fileExists(url) {
            // The file can be pruned between the download returning and the open. Retry only
            // while the originating selection is still current (N3).
            guard isCurrent(origin),
                  let retried = await download(attachment),
                  isCurrent(origin), fileExists(retried) else { return }
            url = retried
        }
        guard isCurrent(origin), fileExists(url) else { return }
        _ = openFile(url)
    }

    func startSave(_ attachment: Attachment) {
        guard saveTask == nil else { return }
        let origin = origin()
        saveErrorText = nil
        saveTask = Task { [weak self] in
            await self?.runSave(attachment, origin: origin)
        }
    }

    private func runSave(_ attachment: Attachment, origin: Origin) async {
        guard saveGate.begin(attachment.id) else {
            saveTask = nil
            return
        }
        defer {
            saveGate.end(attachment.id)
            saving = nil
            saveTask = nil
        }
        guard isCurrent(origin), !Task.isCancelled else { return }
        guard let source = await download(attachment) else { return }
        guard isCurrent(origin), !Task.isCancelled else { return }
        // Only the panel/copy stage shows a cancel affordance; downloads have none (D18).
        saving = (attachment.id, origin)
        let flow = AttachmentSaveFlow(panel: panel, copy: copy, fileExists: fileExists)
        let text = await flow.run(source: source, displayName: attachment.displayName) {
            isCurrent(origin) && !Task.isCancelled
        }
        guard isCurrent(origin) else { return }
        saveErrorText = text
    }

    func cancelSave() {
        saveTask?.cancel()
        saving = nil
    }

    private func origin() -> Origin { Origin(key: currentKey(), epoch: epoch) }

    private func isCurrent(_ origin: Origin) -> Bool {
        currentKey() == origin.key && epoch == origin.epoch
    }
}
