import SwiftUI

struct AuthFlowView: View {
    @Environment(AppStore.self) private var appStore

    @State private var phoneNumber: String = ""
    @State private var verificationCode: String = ""
    @State private var password: String = ""
    @State private var firstName: String = ""
    @State private var lastName: String = ""

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.08),
                    Color(nsColor: .windowBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                headerBrand

                if appStore.hasOtherReadyAccounts {
                    multiAccountReturnBar
                }

                VStack(spacing: 20) {
                    switch appStore.authStep {
                    case .configuring, .loggingOut:
                        loadingSection(
                            title: appStore.authStep == .loggingOut ? "正在退出登录…" : "正在初始化 TDLib…"
                        )

                    case .needsCredentials:
                        APIConfigView()

                    case .waitPhoneNumber:
                        phoneStepView

                    case .waitQRCode(let link):
                        qrCodeStepView(link: link)

                    case .waitCode(let phone, let hint):
                        codeStepView(phone: phone, hint: hint)

                    case .waitPassword(let hint):
                        passwordStepView(hint: hint)

                    case .waitRegistration:
                        registrationStepView

                    case .unsupported(let message):
                        unsupportedStepView(message: message)

                    case .ready:
                        EmptyView()
                    }
                }
                .padding(28)
                .frame(width: 420)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 20, y: 10)

                ConnectionStatusBadge(status: appStore.connectionStatus)
            }
            .padding(32)
        }
    }

    // MARK: - Sections

    private var headerBrand: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.21, green: 0.67, blue: 0.96), Color(red: 0.13, green: 0.52, blue: 0.86)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.accentColor.opacity(0.28), radius: 12, y: 6)

                Image(systemName: "paperplane.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(x: -1, y: 1)
            }

            Text("SwiftUITelegram")
                .font(.title.weight(.bold))

            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var headerSubtitle: String {
        if appStore.activeAccount.isTemporaryAddFlow && appStore.hasOtherReadyAccounts {
            return "添加新 Telegram 账号（现有账号保持在线）"
        }
        if !appStore.activeAccount.isTemporaryAddFlow && appStore.hasOtherReadyAccounts {
            return "账号「\(appStore.activeAccount.displayName)」需要重新登录"
        }
        return "macOS 原生 SwiftUI 客户端"
    }

    private var multiAccountReturnBar: some View {
        HStack(spacing: 10) {
            if appStore.activeAccount.isTemporaryAddFlow {
                Button {
                    appStore.cancelAddingAccount()
                } label: {
                    Label("返回已登录账号", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Menu {
                    ForEach(appStore.readyAccounts) { session in
                        Button(session.displayName) {
                            appStore.switchAccount(to: session.id)
                        }
                    }
                } label: {
                    Label("切换到已登录账号", systemImage: "person.2")
                }
                .controlSize(.small)

                Button("移除此账号", role: .destructive) {
                    appStore.removeAccount(accountId: appStore.activeAccountId)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func loadingSection(title: String) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var phoneStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("登录 Telegram")
                    .font(.title2.weight(.semibold))
                Text("输入带国际区号的手机号，或使用手机端扫码快速登录。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            TextField("+86 138 0013 8000", text: $phoneNumber)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .onSubmit { submitPhone() }

            errorBanner

            Button {
                submitPhone()
            } label: {
                submitButtonLabel("下一步")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appStore.isSubmittingAuth)

            Divider()

            Button {
                Task { await appStore.requestQRCodeLogin() }
            } label: {
                Label("使用二维码扫码登录", systemImage: "qrcode")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(appStore.isSubmittingAuth)
        }
    }

    private func qrCodeStepView(link: String) -> some View {
        VStack(spacing: 16) {
            Text("扫码登录")
                .font(.title2.weight(.semibold))

            QRCodeView(payload: link, size: 196)

            VStack(alignment: .leading, spacing: 6) {
                Text("1. 在手机上打开 Telegram")
                Text("2. 前往 设置 → 设备 → 连接桌面设备")
                Text("3. 扫描上方二维码完成登录")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            errorBanner

            Button("改用手机号登录") {
                Task { await appStore.switchBackToPhoneLogin() }
            }
            .buttonStyle(.link)
            .disabled(appStore.isSubmittingAuth)
        }
    }

    private func codeStepView(phone: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("输入验证码")
                    .font(.title2.weight(.semibold))
                Text(phone)
                    .font(.callout.weight(.medium))
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("5 位验证码", text: $verificationCode)
                .textFieldStyle(.roundedBorder)
                .font(.title3.monospacedDigit())
                .onSubmit { submitCode() }

            errorBanner

            Button {
                submitCode()
            } label: {
                submitButtonLabel("验证")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appStore.isSubmittingAuth)
        }
    }

    private func passwordStepView(hint: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("两步验证密码")
                    .font(.title2.weight(.semibold))
                Text(hint.isEmpty ? "你的账号启用了云端两步验证密码。" : "密码提示：\(hint)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            SecureField("输入两步验证密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitPassword() }

            errorBanner

            Button {
                submitPassword()
            } label: {
                submitButtonLabel("登录")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(password.isEmpty || appStore.isSubmittingAuth)
        }
    }

    private var registrationStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("创建 Telegram 账号")
                    .font(.title2.weight(.semibold))
                Text("该手机号尚未注册，请填写姓名以完成注册。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            TextField("名字（必填）", text: $firstName)
                .textFieldStyle(.roundedBorder)
            TextField("姓氏（可选）", text: $lastName)
                .textFieldStyle(.roundedBorder)

            errorBanner

            Button {
                Task {
                    await appStore.submitRegistration(firstName: firstName, lastName: lastName)
                }
            } label: {
                submitButtonLabel("完成注册")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appStore.isSubmittingAuth)
        }
    }

    private func unsupportedStepView(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "info.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = appStore.authErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func submitButtonLabel(_ text: String) -> some View {
        HStack(spacing: 8) {
            if appStore.isSubmittingAuth {
                ProgressView()
                    .controlSize(.small)
            }
            Text(text)
                .frame(maxWidth: .infinity)
        }
    }

    private func submitPhone() {
        Task { await appStore.submitPhoneNumber(phoneNumber) }
    }

    private func submitCode() {
        Task { await appStore.submitAuthCode(verificationCode) }
    }

    private func submitPassword() {
        Task { await appStore.submitPassword(password) }
    }
}
