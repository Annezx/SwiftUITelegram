import SwiftUI

struct ChatRowView: View {
    let chat: ChatSummary
    let isPinned: Bool

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
            }
        }
        .padding(.vertical, 4)
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
