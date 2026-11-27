import AppKit
import Foundation
import UniformTypeIdentifiers

/// Sandbox-friendly macOS file operations for downloaded Telegram media:
/// Quick Look preparation, Save As panel, Reveal in Finder, Open externally, and Copy Image.
@MainActor
enum MediaFileActions {
    /// Prepares a Quick Look-ready URL with a human-readable filename and proper extension
    /// (TDLib often stores files under internal paths or missing extensions).
    static func quickLookURL(for localPath: String, preferredFileName: String? = nil, mimeType: String? = nil) -> URL {
        let sourceURL = URL(fileURLWithPath: localPath)
        let targetName = resolvedFileName(
            for: sourceURL,
            preferredFileName: preferredFileName,
            mimeType: mimeType
        )

        if sourceURL.lastPathComponent == targetName && !sourceURL.pathExtension.isEmpty {
            return sourceURL
        }

        let stagingDir = AppConfiguration.quickLookStagingDirectory
            .appendingPathComponent(stableSubdirectoryName(for: localPath), isDirectory: true)
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        let stagedURL = stagingDir.appendingPathComponent(targetName)
        if !FileManager.default.fileExists(atPath: stagedURL.path) {
            do {
                try FileManager.default.createSymbolicLink(at: stagedURL, withDestinationURL: sourceURL)
            } catch {
                try? FileManager.default.copyItem(at: sourceURL, to: stagedURL)
            }
        }
        return FileManager.default.fileExists(atPath: stagedURL.path) ? stagedURL : sourceURL
    }

    static func saveFile(from localPath: String, suggestedFileName: String? = nil, mimeType: String? = nil) {
        let sourceURL = URL(fileURLWithPath: localPath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = resolvedFileName(
            for: sourceURL,
            preferredFileName: suggestedFileName,
            mimeType: mimeType
        )

        panel.begin { response in
            guard response == .OK, let destinationURL = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                // Keep UI non-blocking if the user cancels or target volume is read-only.
            }
        }
    }

    static func revealInFinder(localPath: String) {
        let url = URL(fileURLWithPath: localPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openExternally(localPath: String, preferredFileName: String? = nil, mimeType: String? = nil) {
        let url = quickLookURL(for: localPath, preferredFileName: preferredFileName, mimeType: mimeType)
        NSWorkspace.shared.open(url)
    }

    static func copyImageToPasteboard(from localPath: String) {
        guard let image = NSImage(contentsOfFile: localPath) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    static func copyImageToPasteboard(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    // MARK: - Helpers

    private static func resolvedFileName(for sourceURL: URL, preferredFileName: String?, mimeType: String?) -> String {
        let sanitizedPreferred = preferredFileName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")

        var candidate = (sanitizedPreferred?.isEmpty == false ? sanitizedPreferred! : sourceURL.lastPathComponent)
        if candidate.isEmpty {
            candidate = "telegram_media"
        }

        if URL(fileURLWithPath: candidate).pathExtension.isEmpty {
            if !sourceURL.pathExtension.isEmpty {
                candidate += ".\(sourceURL.pathExtension)"
            } else if let mimeType, let ext = UTType(mimeType: mimeType)?.preferredFilenameExtension {
                candidate += ".\(ext)"
            }
        }
        return candidate
    }

    private static func stableSubdirectoryName(for path: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(format: "%016llx", hash)
    }
}
