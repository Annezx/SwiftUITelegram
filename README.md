# SwiftUITelegram

一个面向 **macOS 15+ (Sequoia)** 的原生 SwiftUI Telegram 客户端，底层通过 [Swiftgram/TDLibKit](https://github.com/Swiftgram/TDLibKit) 接入官方 **TDLib**。

## 当前 MVP 已实现功能

- **多方式登录流程**
  - 首次运行内置 API 凭证引导（也支持 `Config/Secrets.xcconfig` 或环境变量注入）
  - 手机号 + 验证码登录
  - **二维码扫码登录**（基于原生 CoreImage 生成二维码）
  - 两步验证（2FA）云端密码 & 新用户注册
- **原生 macOS 三栏式 / 双栏式体验**
  - `NavigationSplitView` 会话列表 + 聊天详情
  - 严格遵循 TDLib `(order, chat.id)` 排序规则，支持置顶、未读计数、全部对话 / 已归档切换
  - 本地 + 远端会话搜索（快捷键 `⌘K`）
  - 头像与图片消息按需下载 + `NSCache` 缓存
- **现代 SwiftUI (macOS 15+) 消息时间线**
  - 使用 `ScrollPosition` + `.defaultScrollAnchor(.bottom)` + `.onScrollGeometryChange` 实现底部锚定、上滑自动分页加载历史消息与「回到底部」悬浮按钮
  - 实时收发文本消息、已编辑标记、发送中 / 已读状态回执、右键复制
  - 原生 macOS `Settings` 窗口（`⌘,`）与优雅退出清理 TDLib 数据库

详细的架构设计与后续路线图请参阅 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

---

## 环境要求

- **macOS 15.0+** (Sequoia)
- **Xcode 16.0+**
- Telegram 开发者凭证 `api_id` 和 `api_hash`（前往 [my.telegram.org/apps](https://my.telegram.org/apps) 免费申请）

---

## 快速开始

### 方式一：使用 XcodeGen 生成完整 `.app` 工程（推荐）

```bash
chmod +x Scripts/bootstrap.sh
./Scripts/bootstrap.sh
open SwiftUITelegram.xcodeproj
```

> 首次打开 Xcode 时，Swift Package Manager 会下载 `TDLibFramework` 预编译二进制包（约 300 MB），请保持网络畅通并耐心等待解析完成。

可选：在 `Config/Secrets.xcconfig`（已被 `.gitignore` 忽略）中填入凭证：

```xcconfig
TELEGRAM_API_ID = 12345678
TELEGRAM_API_HASH = your_32_char_api_hash
```

如果暂不修改 `Secrets.xcconfig`，也可以直接运行应用，在首次启动界面中填写 `api_id` 和 `api_hash`。

### 方式二：直接用 Xcode 打开 `Package.swift`

无需安装 XcodeGen，直接用 Xcode 16 打开仓库根目录下的 `Package.swift`，选择 `SwiftUITelegram` Scheme 并按下 `⌘R` 即可运行。

---

## 目录结构

```text
SwiftUITelegram/
├── Package.swift                          # SwiftPM 配置（macOS 15+，固定 TDLibKit 版本）
├── project.yml                            # XcodeGen 工程描述
├── Config/
│   ├── Secrets.xcconfig.example           # Telegram API 凭证模板
│   └── SwiftUITelegram.entitlements       # macOS Sandbox 与网络权限
├── Resources/
│   └── Info.plist
├── Scripts/
│   └── bootstrap.sh                       # 一键初始化 Secrets 并生成 .xcodeproj
├── docs/
│   └── ARCHITECTURE.md                    # 架构设计与分阶段路线图
└── Sources/SwiftUITelegram/
    ├── App/                               # 入口、AppDelegate 优雅退出、配置读取
    ├── Core/
    │   ├── TDLib/                         # TDLibService 封装与错误处理
    │   ├── Media/                         # FileCacheStore 文件下载与图片缓存
    │   └── Models/                        # 轻量 UI 领域模型与状态机
    ├── Stores/                            # AppStore / ChatListStore / ConversationStore
    └── Features/                          # Auth / Main / ChatList / Conversation / Components
```