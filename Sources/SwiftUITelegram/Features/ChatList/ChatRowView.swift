import SwiftUI

struct ChatRowView: View {
    let chat: ChatSummary
    let isPinned: Bool
    var folderTags: [ChatFolderItem] = []

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(
                title: chat.title,
                initials: chat.avatarInitials,
                accentSeed: chat.accentColorId,
                fileId: chat.smallPhotoFileId,
                knownLocalPath: chat.smallPhotoLocalPath,
                size: 42
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if chat.kind.isChannel {
                        Image(systemName: "megaphone.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if case .secret = chat.kind {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }

                    Text(chat.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if chat.isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 4)

                    if let date = chat.lastMessageDate {
                        Text(Self.formatTimestamp(date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                HStack(spacing: 6) {
                    Text(chat.lastMessagePreview)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    unreadBadge
                }

                if !folderTags.isEmpty {
                    folderTagStrip
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var folderTagStrip: some View {
        let visibleTags = Array(folderTags.prefix(3))
        let overflowCount = max(0, folderTags.count - visibleTags.count)

        return HStack(spacing: 4) {
            ForEach(visibleTags) { folder in
                let tint = ChatFolderColorPalette.color(for: folder.colorId) ?? Color.accentColor
                Text(folder.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            if overflowCount > 0 {
                Text("+\(overflowCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .padding(.top, 1)
    }

    @ViewBuilder
    private var unreadBadge: some View {
        let badgeColor: Color = chat.isMuted ? Color.secondary.opacity(0.45) : Color.accentColor
        if chat.unreadCount > 0 {
            Text(chat.unreadCount > 999 ? "999+" : "\(chat.unreadCount)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badgeColor, in: Capsule())
        } else if chat.isMarkedAsUnread {
            Circle()
                .fill(badgeColor)
                .frame(width: 9, height: 9)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        return f
    }()

    private static func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return timeFormatter.string(from: date)
        }
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: .now), date > weekAgo {
            return weekdayFormatter.string(from: date)
        }
        return shortDateFormatter.string(from: date)
    }
}
