import AppKit
import Foundation
import Observation
import TDLibKit

/// Coordinates TDLib file downloads, listens to `updateFile`, and caches decoded `NSImage` instances.
@MainActor
@Observable
final class FileCacheStore {
    private let service: TDLibService
    private let imageCache = NSCache<NSNumber, NSImage>()
    private var inFlightFileIds: Set<Int> = []

    /// Reactive map of `fileId -> completed local file path`.
    private(set) var localPaths: [Int: String] = [:]

    init(service: TDLibService) {
        self.service = service
        self.imageCache.countLimit = 250
    }

    func image(for fileId: Int, knownLocalPath: String? = nil) -> NSImage? {
        let key = NSNumber(value: fileId)
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        let path = localPaths[fileId] ?? knownLocalPath
        if let path, !path.isEmpty, let image = NSImage(contentsOfFile: path) {
            imageCache.setObject(image, forKey: key)
            return image
        }
        return nil
    }

    func ensureDownloaded(fileId: Int, priority: Int = 16) {
        if let existing = localPaths[fileId], !existing.isEmpty {
            return
        }
        guard !inFlightFileIds.contains(fileId) else { return }
        inFlightFileIds.insert(fileId)

        Task {
            defer { inFlightFileIds.remove(fileId) }
            do {
                let file = try await service.downloadFile(fileId: fileId, priority: priority)
                handleFileUpdate(file)
            } catch {
                // Keep UI silent on background thumbnail/avatar fetch failures.
            }
        }
    }

    func handleFileUpdate(_ file: File) {
        if file.local.isDownloadingCompleted, !file.local.path.isEmpty {
            localPaths[file.id] = file.local.path
            if let img = NSImage(contentsOfFile: file.local.path) {
                imageCache.setObject(img, forKey: NSNumber(value: file.id))
            }
        }
    }

    func reset() {
        localPaths.removeAll()
        inFlightFileIds.removeAll()
        imageCache.removeAllObjects()
    }
}
