import SwiftUI

enum ChatDestructiveActionKind: Equatable {
    case clearHistory
    case deleteOrLeave
}

struct ChatActionConfirmationRequest: Identifiable, Equatable {
    let id = UUID()
    let chat: ChatSummary
    let kind: ChatDestructiveActionKind

    var supportsRevokeOption: Bool {
        switch chat.kind {
        case .privateUser, .secret:
            return chat.canBeDeletedForAllUsers && chat.canBeDeletedOnlyForSelf
        case .basicGroup, .supergroup, .channel:
            return false
        }
    }

    var title: String {
        switch kind {
        case .clearHistory:
            return "清空「\(chat.title)」的聊天记录？"
        case .deleteOrLeave:
            switch chat.kind {
            case .privateUser, .secret:
                return "删除与「\(chat.title)」的对话？"
            case .basicGroup, .supergroup:
                return "退出群组「\(chat.title)」？"
            case .channel:
                return "退出频道「\(chat.title)」？"
            }
        }
    }

    var descriptionText: String {
        switch kind {
        case .clearHistory:
            return "该对话中的消息将被清空，对话仍会保留在列表中。"
        case .deleteOrLeave:
            switch chat.kind {
            case .privateUser, .secret:
                return "此操作将清空消息并从您的对话列表中移除该对话。"
            case .basicGroup, .supergroup:
                return "退出后您将不再接收此群组的消息，并从对话列表中移除。"
            case .channel:
                return "退出后您将不再接收此频道的新内容。"
            }
        }
    }

    var confirmButtonTitle: String {
        switch kind {
        case .clearHistory:
            return "清空记录"
        case .deleteOrLeave:
            switch chat.kind {
            case .privateUser, .secret:
                return "删除对话"
            case .basicGroup, .supergroup:
                return "退出群组"
            case .channel:
                return "退出频道"
            }
        }
    }

    var revokeCheckboxTitle: String {
        switch kind {
        case .clearHistory:
            return "同时为「\(chat.title)」清空记录"
        case .deleteOrLeave:
            return "同时为「\(chat.title)」删除对话"
        }
    }

    var symbolName: String {
        switch kind {
        case .clearHistory:
            return "eraser.fill"
        case .deleteOrLeave:
            switch chat.kind {
            case .privateUser, .secret:
                return "trash.circle.fill"
            case .basicGroup, .supergroup, .channel:
                return "rectangle.portrait.and.arrow.right.fill"
            }
        }
    }
}

struct ChatActionConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let request: ChatActionConfirmationRequest
    let onConfirm: (_ revoke: Bool) async -> Bool

    @State private var revokeForAll: Bool = false
    @State private var isWorking: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(
                    title: request.chat.title,
                    initials: request.chat.avatarInitials,
                    accentSeed: request.chat.accentColorId,
                    fileId: request.chat.smallPhotoFileId,
                    knownLocalPath: request.chat.smallPhotoLocalPath,
                    size: 40
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(request.title)
                        .font(.headline)

                    Text(request.descriptionText)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if request.supportsRevokeOption {
                        Toggle(request.revokeCheckboxTitle, isOn: $revokeForAll)
                            .toggleStyle(.checkbox)
                            .padding(.top, 2)
                    }
                }
            }

            HStack(spacing: 10) {
                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)

                Button(role: .destructive) {
                    Task {
                        isWorking = true
                        let effectiveRevoke = request.supportsRevokeOption ? revokeForAll : false
                        let ok = await onConfirm(effectiveRevoke)
                        isWorking = false
                        if ok {
                            dismiss()
                        }
                    }
                } label: {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 64)
                    } else {
                        Text(request.confirmButtonTitle)
                            .frame(minWidth: 64)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking)
            }
        }
        .padding(20)
        .frame(width: 410)
    }
}
