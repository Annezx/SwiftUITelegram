import SwiftUI

struct APIConfigView: View {
    @Environment(AppStore.self) private var appStore

    @State private var apiIdText: String = ""
    @State private var apiHash: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("配置 Telegram API 凭证")
                    .font(.title2.weight(.semibold))
                Text("每个自研 Telegram 客户端都需要先在 my.telegram.org 申请 api_id 和 api_hash。凭证仅保存在本机。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let portalURL = URL(string: "https://my.telegram.org/apps") {
                Link(destination: portalURL) {
                    Label("打开 my.telegram.org/apps 获取凭证", systemImage: "arrow.up.right.square")
                        .font(.callout.weight(.medium))
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("API ID")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("例如：12345678", text: $apiIdText)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("API Hash")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    SecureField("32 位字符串", text: $apiHash)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let error = appStore.authErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    await appStore.submitCredentials(apiIdText: apiIdText, apiHash: apiHash)
                }
            } label: {
                HStack {
                    if appStore.isSubmittingAuth {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("保存并继续")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(apiIdText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || apiHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || appStore.isSubmittingAuth)
        }
    }
}
