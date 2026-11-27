import AppKit
import SwiftUI

struct AvatarView: View {
    @Environment(AppStore.self) private var appStore

    let title: String
    let initials: String
    let accentSeed: Int
    let fileId: Int?
    let knownLocalPath: String?
    var size: CGFloat = 40
    var fileCache: FileCacheStore? = nil

    private struct DownloadTaskKey: Equatable {
        let fileId: Int?
        let cacheId: ObjectIdentifier
    }

    private var resolvedFileCache: FileCacheStore {
        fileCache ?? appStore.fileCache
    }

    private static let palettes: [(Color, Color)] = [
        (Color(red: 0.94, green: 0.42, blue: 0.36), Color(red: 0.85, green: 0.27, blue: 0.29)),
        (Color(red: 0.95, green: 0.62, blue: 0.25), Color(red: 0.88, green: 0.45, blue: 0.16)),
        (Color(red: 0.56, green: 0.44, blue: 0.92), Color(red: 0.42, green: 0.31, blue: 0.82)),
        (Color(red: 0.31, green: 0.76, blue: 0.44), Color(red: 0.18, green: 0.63, blue: 0.34)),
        (Color(red: 0.22, green: 0.70, blue: 0.82), Color(red: 0.14, green: 0.55, blue: 0.72)),
        (Color(red: 0.27, green: 0.58, blue: 0.94), Color(red: 0.16, green: 0.44, blue: 0.85)),
        (Color(red: 0.90, green: 0.39, blue: 0.65), Color(red: 0.78, green: 0.25, blue: 0.52)),
    ]

    private var palette: (Color, Color) {
        let index = abs(accentSeed) % Self.palettes.count
        return Self.palettes[index]
    }

    var body: some View {
        let cache = resolvedFileCache
        Group {
            if let fileId, let image = cache.image(for: fileId, knownLocalPath: knownLocalPath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [palette.0, palette.1],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Text(initials.isEmpty ? String(title.prefix(1)).uppercased() : initials)
                        .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: DownloadTaskKey(fileId: fileId, cacheId: ObjectIdentifier(cache))) {
            if let fileId {
                cache.ensureDownloaded(fileId: fileId, priority: 12)
            }
        }
    }
}
