import SwiftUI

struct ConversationView: View {
    @Environment(AppStore.self) private var appStore

    let chat: ChatSummary

    @State private var scrollPosition = ScrollPosition(idType: Int64.self)
    @State private var isNearBottom: Bool = true

    var body: some View {
        @Bindable var conversation = appStore.conversation

        VStack(spacing: 0) {
            headerBar

            Divider()

            ZStack(alignment: .bottomTrailing) {
                messageTimeline(messages: conversation.messages)

                if !isNearBottom && !conversation.messages.isEmpty {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            scrollPosition.scrollTo(edge: .bottom)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isNearBottom)

            if let error = conversation.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button {
                        conversation.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.red.opacity(0.08))
            }

            Divider()

            MessageComposerView(
                text: $conversation.draftText,
                isSending: conversation.isSending,
                onSend: {
                    Task { await conversation.sendCurrentDraft() }
                }
            )
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .onChange(of: conversation.scrollToBottomTrigger) { _, _ in
            withAnimation(.snappy(duration: 0.2)) {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
        .onChange(of: conversation.messages.last?.id) { _, _ in
            if isNearBottom {
                withAnimation(.snappy(duration: 0.2)) {
                    scrollPosition.scrollTo(edge: .bottom)
                }
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            AvatarView(
                title: chat.title,
                initials: chat.avatarInitials,
                accentSeed: chat.accentColorId,
                fileId: chat.smallPhotoFileId,
                knownLocalPath: chat.smallPhotoLocalPath,
                size: 36
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(chat.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(appStore.chatList.subtitle(for: chat))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func messageTimeline(messages: [MessageItem]) -> some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if appStore.conversation.isLoadingOlder {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.vertical, 10)
                } else if !appStore.conversation.hasMoreOlder && !messages.isEmpty {
                    Text("已加载全部历史消息")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 10)
                }

                if appStore.conversation.isLoadingInitial && messages.isEmpty {
                    ProgressView("正在加载消息…")
                        .padding(.top, 80)
                } else if messages.isEmpty {
                    ContentUnavailableView(
                        "暂无消息",
                        systemImage: "text.bubble",
                        description: Text("发送第一条消息开始聊天吧。")
                    )
                    .padding(.top, 80)
                } else {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        if shouldShowDateDivider(at: index, in: messages) {
                            dateSeparator(for: message.date)
                        }

                        MessageBubbleView(
                            message: message,
                            senderName: shouldShowSenderName(for: message)
                                ? appStore.chatList.senderDisplayName(for: message.sender)
                                : nil,
                            isReadByRecipient: message.isOutgoing && message.id <= chat.lastReadOutboxMessageId
                        )
                        .id(message.id)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            let distanceFromBottom = geometry.contentSize.height - geometry.visibleRect.maxY
            return distanceFromBottom <= 80
        } action: { _, nearBottom in
            isNearBottom = nearBottom
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            let hasScrollableOverflow = geometry.contentSize.height > geometry.containerSize.height + 40
            return hasScrollableOverflow && geometry.visibleRect.minY <= 80
        } action: { oldNearTop, newNearTop in
            if newNearTop && !oldNearTop {
                Task { await appStore.conversation.loadOlderMessages() }
            }
        }
    }

    private func shouldShowSenderName(for message: MessageItem) -> Bool {
        chat.kind.isGroup && !message.isOutgoing
    }

    private func shouldShowDateDivider(at index: Int, in messages: [MessageItem]) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(messages[index - 1].date, inSameDayAs: messages[index].date)
    }

    private func dateSeparator(for date: Date) -> some View {
        Text(Self.dateDividerFormatter.string(from: date))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .padding(.vertical, 8)
    }

    private static let dateDividerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
