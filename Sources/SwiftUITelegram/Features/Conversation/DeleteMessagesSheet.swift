import SwiftUI

struct DeleteMessagesRequest: Identifiable, Equatable {
    let id = UUID()
    let chatId: Int64
    let chatTitle: String
    let chatKind: ChatKind
    let messages: [MessageItem]
    let canDeleteForSelf: Bool
    let canDeleteForAll: Bool

    var messageIds: [Int64] {
        messages.map(\.id)
    }

    var defaultRevoke: Bool {
        if canDeleteForAll && !canDeleteForSelf {
            return true
        }
        if canDeleteForSelf && !canDeleteForAll {
            return false
        }
        return messages.allSatisfy(\.isOutgoing)
    }
}

struct DeleteMessagesSheet: View {
    @Environment(\.dismiss) private var dismiss

    let request: DeleteMessagesRequest
    let onConfirm: (_ revoke: Bool) async -> Bool

    @State private var revokeForAll: Bool
    @State private var isDeleting: Bool = false

    init(
        request: DeleteMessagesRequest,
        onConfirm: @escaping (_ revoke: Bool) async -> Bool
    ) {
        self.request = request
        self.onConfirm = onConfirm
        self._revokeForAll = State(initialValue: request.defaultRevoke)
    }

    private var titleText: String {
        request.messages.count == 1
            ? "删除这条消息？"
            : "删除选中的 \(request.messages.count) 条消息？"
    }

    private var revokeCheckboxTitle: String {
        switch request.chatKind {
        case .privateUser, .secret:
            return "同时为「\(request.chatTitle)」删除"
        case .basicGroup, .supergroup, .channel:
            return "同时为所有成员删除"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 6) {
                    Text(titleText)
                        .font(.headline)

                    if request.messages.count == 1, let preview = request.messages.first?.previewText, !preview.isEmpty {
                        Text(preview)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                Color(nsColor: .controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                    }

                    if request.canDeleteForSelf && request.canDeleteForAll {
                        Toggle(revokeCheckboxTitle, isOn: $revokeForAll)
                            .toggleStyle(.checkbox)
                            .padding(.top, 2)
                    } else if request.canDeleteForAll {
                        Text("此操作将为该对话中的所有成员永久删除，且无法撤销。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("此操作仅会从您的本地及云端记录中删除。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 10) {
                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isDeleting)

                Button(role: .destructive) {
                    Task {
                        isDeleting = true
                        let effectiveRevoke: Bool
                        if request.canDeleteForAll && !request.canDeleteForSelf {
                            effectiveRevoke = true
                        } else if request.canDeleteForSelf && !request.canDeleteForAll {
                            effectiveRevoke = false
                        } else {
                            effectiveRevoke = revokeForAll
                        }
                        let ok = await onConfirm(effectiveRevoke)
                        isDeleting = false
                        if ok {
                            dismiss()
                        }
                    }
                } label: {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 44)
                    } else {
                        Text("删除")
                            .frame(minWidth: 44)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
                .disabled(isDeleting)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
