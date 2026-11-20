import Foundation
import TDLibKit

enum AuthStep: Equatable, Sendable {
    case configuring
    case needsCredentials
    case waitPhoneNumber
    case waitQRCode(link: String)
    case waitCode(phoneNumber: String, deliveryHint: String)
    case waitPassword(hint: String)
    case waitRegistration
    case ready
    case loggingOut
    case unsupported(String)

    static func from(_ state: AuthorizationState) -> AuthStep {
        switch state {
        case .authorizationStateWaitTdlibParameters:
            return .configuring
        case .authorizationStateWaitPhoneNumber:
            return .waitPhoneNumber
        case .authorizationStateWaitOtherDeviceConfirmation(let info):
            return .waitQRCode(link: info.link)
        case .authorizationStateWaitCode(let info):
            let hint: String
            switch info.codeInfo.type {
            case .authenticationCodeTypeTelegramMessage:
                hint = "验证码已发送至你的其他 Telegram 设备。"
            case .authenticationCodeTypeSms, .authenticationCodeTypeSmsWord, .authenticationCodeTypeSmsPhrase:
                hint = "验证码已通过短信发送。"
            case .authenticationCodeTypeCall, .authenticationCodeTypeFlashCall, .authenticationCodeTypeMissedCall:
                hint = "Telegram 正在通过语音电话发送验证码。"
            default:
                hint = "请输入收到的登录验证码。"
            }
            return .waitCode(phoneNumber: info.codeInfo.phoneNumber, deliveryHint: hint)
        case .authorizationStateWaitPassword(let info):
            return .waitPassword(hint: info.passwordHint)
        case .authorizationStateWaitRegistration:
            return .waitRegistration
        case .authorizationStateReady:
            return .ready
        case .authorizationStateLoggingOut, .authorizationStateClosing, .authorizationStateClosed:
            return .loggingOut
        case .authorizationStateWaitEmailAddress:
            return .unsupported("该账号需要先绑定或验证邮箱（MVP 暂未实现邮箱验证界面）。")
        case .authorizationStateWaitEmailCode:
            return .unsupported("该账号需要输入邮箱验证码（MVP 暂未实现邮箱验证界面）。")
        case .authorizationStateWaitPremiumPurchase:
            return .unsupported("当前登录需要完成 Telegram Premium 订阅验证。")
        }
    }
}

enum ConnectionStatus: Equatable, Sendable {
    case waitingForNetwork
    case connectingToProxy
    case connecting
    case updating
    case ready

    init(from state: ConnectionState) {
        switch state {
        case .connectionStateWaitingForNetwork:
            self = .waitingForNetwork
        case .connectionStateConnectingToProxy:
            self = .connectingToProxy
        case .connectionStateConnecting:
            self = .connecting
        case .connectionStateUpdating:
            self = .updating
        case .connectionStateReady:
            self = .ready
        }
    }

    var displayText: String? {
        switch self {
        case .waitingForNetwork:
            return "等待网络…"
        case .connectingToProxy:
            return "正在连接代理…"
        case .connecting:
            return "正在连接…"
        case .updating:
            return "同步中…"
        case .ready:
            return nil
        }
    }
}
