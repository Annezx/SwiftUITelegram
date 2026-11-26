import AppKit
import Foundation
import Observation
import TDLibKit

/// Coordinates TDLib file downloads/uploads, reacts to `updateFile`, tracks transfer progress,
/// and lazily caches decoded `NSImage` instances and minithumbnails.
@MainActor
@Observable
final class FileCacheStore {
    private let service: TDLibService
    private let imageCache = NSCache<NSNumber, NSImage>()
    private let minithumbnailCache = NSCache<NSData, NSImage>()
    private var inFlightDownloadIds: Set<Int> = []

    /// Reactive map of `fileId -> FileTransferState` (download/upload progress and local path).
    private(set) var transferStates: [Int: FileTransferState] = [:]

    init(service: TDLibService) {
        self.service = service
        self.imageCache.countLimit = 300
        self.minithumbnailCache.countLimit = 400
    }

    // MARK: - State Queries

    func state(for descriptor: MediaFileDescriptor) -> FileTransferState {
        if let tracked = transferStates[descriptor.fileId] {
            return tracked
        }
        return FileTransferState(descriptor: descriptor)
    }

    func localPath(for descriptor: MediaFileDescriptor) -> String? {
        let current = state(for: descriptor)
        guard current.isDownloaded, let path = current.localPath, !path.isEmpty else {
            return nil
        }
        return path
    }

    func localPath(for fileId: Int, fallback: String? = nil) -> String? {
        if let tracked = transferStates[fileId] {
            if tracked.isDownloaded, let path = tracked.localPath, !path.isEmpty {
                return path
            }
            return nil
        }
        if let fallback, !fallback.isEmpty {
            return fallback
        }
        return nil
    }

    // MARK: - Image Decoding & Caching

    func image(for fileId: Int, knownLocalPath: String? = nil) -> NSImage? {
        // Always touch `transferStates` first so `@Observable` registers a dependency
        // even before the file finishes downloading.
        let tracked = transferStates[fileId]
        let key = NSNumber(value: fileId)

        if let cached = imageCache.object(forKey: key) {
            return cached
        }

        let candidatePath: String?
        if let tracked {
            candidatePath = tracked.isDownloaded ? tracked.localPath : nil
        } else {
            candidatePath = knownLocalPath
        }

        guard let path = candidatePath, !path.isEmpty, let decoded = NSImage(contentsOfFile: path) else {
            return nil
        }
        imageCache.setObject(decoded, forKey: key)
        return decoded
    }

    func image(for descriptor: MediaFileDescriptor) -> NSImage? {
        image(for: descriptor.fileId, knownLocalPath: descriptor.initialLocalPath)
    }

    func minithumbnailImage(for data: Data?) -> NSImage? {
        guard let data, !data.isEmpty else { return nil }
        let key = data as NSData
        if let cached = minithumbnailCache.object(forKey: key) {
            return cached
        }
        guard let img = NSImage(data: data) else { return nil }
        minithumbnailCache.setObject(img, forKey: key)
        return img
    }

    // MARK: - Download Control

    /// Auto-downloads lightweight assets (avatars, thumbnails, photos, stickers, GIFs) if not already local.
    func ensureDownloaded(fileId: Int, priority: Int = 16) {
        if let tracked = transferStates[fileId] {
            if tracked.isDownloaded || tracked.isDownloading {
                return
            }
        }
        requestDownload(fileId: fileId, priority: priority)
    }

    func ensureDownloaded(_ descriptor: MediaFileDescriptor, priority: Int = 16) {
        let current = state(for: descriptor)
        if current.isDownloaded {
            if let path = current.localPath, FileManager.default.fileExists(atPath: path) {
                return
            }
        }
        if current.isDownloading {
            return
        }
        requestDownload(fileId: descriptor.fileId, priority: priority)
    }

    /// Explicitly triggered download (for videos, documents, audio, voice notes).
    func startDownload(fileId: Int, priority: Int = 24) {
        requestDownload(fileId: fileId, priority: priority)
    }

    func cancelDownload(fileId: Int) {
        inFlightDownloadIds.remove(fileId)
        Task {
            do {
                try await service.cancelDownloadFile(fileId: fileId, onlyIfPending: false)
                let refreshed = try await service.getFile(fileId: fileId)
                handleFileUpdate(refreshed)
            } catch {
                // Ignore cancellation race if download already completed.
            }
        }
    }

    // MARK: - TDLib Updates

    func handleFileUpdate(_ file: File) {
        let next = FileTransferState(tdFile: file)

        if let prev = transferStates[file.id] {
            let stateChanged =
                prev.isDownloaded != next.isDownloaded
                || prev.isDownloading != next.isDownloading
                || prev.isUploading != next.isUploading
                || prev.isUploaded != next.isUploaded
                || prev.localPath != next.localPath
                || prev.expectedSize != next.expectedSize

            if !stateChanged {
                let dlDelta = abs(next.downloadProgress - prev.downloadProgress)
                let ulDelta = abs(next.uploadProgress - prev.uploadProgress)
                if dlDelta < 0.015 && ulDelta < 0.015 {
                    return
                }
            }

            if prev.localPath != next.localPath {
                imageCache.removeObject(forKey: NSNumber(value: file.id))
            }
        }

        transferStates[file.id] = next
        if next.isDownloaded || !next.isDownloading {
            inFlightDownloadIds.remove(file.id)
        }
    }

    func reset() {
        transferStates.removeAll()
        inFlightDownloadIds.removeAll()
        imageCache.removeAllObjects()
        minithumbnailCache.removeAllObjects()
    }

    // MARK: - Private

    private func requestDownload(fileId: Int, priority: Int) {
        guard !inFlightDownloadIds.contains(fileId) else { return }
        inFlightDownloadIds.insert(fileId)

        Task {
            do {
                let file = try await service.downloadFile(fileId: fileId, priority: priority)
                handleFileUpdate(file)
                if !file.local.isDownloadingActive {
                    inFlightDownloadIds.remove(fileId)
                }
            } catch {
                inFlightDownloadIds.remove(fileId)
            }
        }
    }
}
