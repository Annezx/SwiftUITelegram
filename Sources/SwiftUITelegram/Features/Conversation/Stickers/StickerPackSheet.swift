import AppKit
import SwiftUI

/// Modal sheet displaying all stickers in a Telegram sticker pack, with live hover animation,
/// one-click send to the active conversation, favorite management, and pack install/remove controls.
struct StickerPackSheet: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.dismiss) private var dismiss

    let setId: Int64
    let onSendSticker: (StickerItem) -> Void

    @State private var isLoading: Bool = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    private var detail: StickerPackDetail? {
        appStore.stickers.loadedSetDetails[setId]
    }

    private var isInstalled: Bool {
        appStore.stickers.isSetInstalled(setId)
    }

    private var isMutating: Bool {
        appStore.stickers.mutatingSetIds.contains(setId)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentArea
            Divider()
            footerBar
        }
        .frame(width: 480, height: 500)
        .task(id: setId) {
            isLoading = (detail == nil)
            await appStore.stickers.loadStickerSet(id: setId)
            isLoading = false
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            if let thumb = detail?.thumbnail {
                AnimatedStickerSurfaceView(
                    thumbnailInfo: thumb,
                    size: CGSize(width: 38, height: 38),
                    isPlaying: true,
                    maxPixelSize: 96,
                    downloadPriority: 20
                )
            } else if let first = detail?.stickers.first {
                AnimatedStickerSurfaceView(
                    sticker: first,
                    size: CGSize(width: 38, height: 38),
                    isPlaying: true,
                    firstFrameOnly: false,
                    maxPixelSize: 96,
                    downloadPriority: 20
                )
            } else {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(detail?.title ?? "正在加载贴纸包…")
                        .font(.headline)
                        .lineLimit(1)

                    if detail?.isOfficial == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                HStack(spacing: 6) {
                    if let count = detail?.stickers.count {
                        Text("\(count) 张贴纸")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let fmt = detail?.formatSummary {
                        Text(fmt)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("关闭 (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var contentArea: some View {
        if isLoading && detail == nil {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在获取贴纸包详情…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detail, !detail.stickers.isEmpty {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(detail.stickers) { sticker in
                        StickerPickerTileView(
                            sticker: sticker,
                            isFavorite: appStore.stickers.isFavorite(sticker),
                            showRemoveFromRecent: false,
                            tileSize: 80,
                            onSend: { keepOpen in
                                onSendSticker(sticker)
                                if !keepOpen {
                                    dismiss()
                                }
                            },
                            onToggleFavorite: {
                                Task { _ = await appStore.stickers.toggleFavorite(sticker) }
                            },
                            onRemoveRecent: nil,
                            onOpenPack: nil
                        )
                    }
                }
                .padding(14)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("无法加载该贴纸包内容")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            Text("悬停可预览动画，点击贴纸即可直接发送")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if detail != nil {
                Button(role: isInstalled ? .destructive : nil) {
                    Task {
                        let targetInstalled = !isInstalled
                        let ok = await appStore.stickers.setStickerSetInstalled(
                            setId: setId,
                            installed: targetInstalled
                        )
                        if ok {
                            appStore.conversation.showTransientNotice(
                                targetInstalled ? "已添加贴纸包「\(detail?.title ?? "")」" : "已移除贴纸包"
                            )
                        }
                    }
                } label: {
                    if isMutating {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 96)
                    } else {
                        Label(
                            isInstalled ? "移除贴纸包" : "添加贴纸包",
                            systemImage: isInstalled ? "trash" : "plus.circle.fill"
                        )
                        .frame(minWidth: 96)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(isInstalled ? .red : .accentColor)
                .disabled(isMutating)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
