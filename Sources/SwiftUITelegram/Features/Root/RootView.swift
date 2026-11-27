import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if appStore.authStep == .ready {
                    MainSplitView()
                        .id(appStore.activeAccountId)
                        .transition(.opacity)
                } else {
                    AuthFlowView()
                        .id(appStore.activeAccountId)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appStore.authStep == .ready)
            .animation(.easeInOut(duration: 0.16), value: appStore.activeAccountId)

            if let notice = appStore.noticeMessage {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(notice)
                        .font(.callout)
                    Button {
                        appStore.noticeMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(MainWindowAccessor())
    }
}
