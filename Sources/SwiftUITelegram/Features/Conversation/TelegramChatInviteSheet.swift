import AppKit
import SwiftUI

/// Native macOS sheet displaying a private Telegram group or channel invite preview
/// (`t.me/+...`, `t.me/joinchat/...`, `tg://join?invite=...`) with one-click join.
struct TelegramChatInviteSheet: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.dismiss) private var dismiss

    let invite: PendingChatInvitePreview

    @State private var isJoining: Bool = false
    @State private var errorMessage: String?

    private var primaryActionTitle: String {
        if invite.createsJoinRequest {
            return "申请加入"
        }
        return invite.isChannel ? "加入频道" : "加入群组"
    }

    private var memberCountText: String {
        if invite.memberCount <= 0 {
            return invite.chatTypeLabel
        }
        return invite.isChannel
            ? "\(invite.chatTypeLabel) · \(invite.memberCount) 位订阅者"
            : "\(invite.chatTypeLabel) · \(invite.memberCount) 位成员"
    }

    private var canOpenInBrowser: Bool {
        guard let scheme = invite.originalURL.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    var body: some View {
        VStack(spacing: 16) {
            AvatarView(
                title: invite.title,
                initials: invite.avatarInitials,
                accentSeed: invite.accentColorId,
                fileId: invite.smallPhotoFileId,
                knownLocalPath: invite.smallPhotoLocalPath,
                size: 72
            )
            .padding(.top, 4)

            VStack(spacing: 6) {
                Text(invite.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(memberCountText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.6), in: Capsule())
            }

            if !invite.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    Text(invite.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 6)
                }
                .frame(maxHeight: 96)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(
                    Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }

            if invite.createsJoinRequest {
                Label("该链接需要管理员审批通过后才可加入。", systemImage: "person.badge.clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let errorMessage {
                VStack(spacing: 8) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if canOpenInBrowser {
                        Button("在浏览器中打开原链接") {
                            NSWorkspace.shared.open(invite.originalURL)
                            appStore.pendingChatInvite = nil
                            dismiss()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
                .padding(10)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Divider()

            HStack(spacing: 10) {
                Button("取消") {
                    appStore.pendingChatInvite = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isJoining)

                Spacer()

                Button {
                    Task { await performJoin() }
                } label: {
                    if isJoining {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在加入…")
                        }
                    } else {
                        Text(primaryActionTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isJoining)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func performJoin() async {
        guard !isJoining else { return }
        isJoining = true
        errorMessage = nil
        let err = await appStore.confirmJoinPendingInvite()
        isJoining = false
        if let err {
            errorMessage = err
        } else {
            dismiss()
        }
    }
}
