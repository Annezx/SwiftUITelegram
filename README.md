# SwiftUITelegram

一个面向 **macOS 15+ (Sequoia)** 的原生 SwiftUI Telegram 客户端，底层通过 [Swiftgram/TDLibKit](https://github.com/Swiftgram/TDLibKit) 接入官方 **TDLib**。

## 当前 MVP 已实现功能

- **多账号同时在线与即时切换**
  - 单 `TDLibClientManager` (`TDLibClientHub`) 复用多 `TDLibClient` 实例，各账号隔离独立的数据库、媒体文件目录与 `FileCacheStore`（零 `fileId` 冲突）
  - 升级保留原单账号会话目录（`tdlib/db` + `tdlib/files`），无需重新登录
  - 侧边栏底部账号切换弹窗显示各后台账号实时未读数，支持 `⌘1`–`⌘9` 快捷键即时切换与 `⇧⌘A` 添加新账号
  - 自动向 Telegram 二维码登录传入 `otherUserIds`，并检测重复登录同一账号自动切换与清理冗余会话
  - 设置窗口（`⌘,`）支持查看全部账号、逐个退出登录或移除失效账号
- **多方式登录流程**
  - 首次运行内置 API 凭证引导（也支持 `Config/Secrets.xcconfig` 或环境变量注入）
  - 手机号 + 验证码登录
  - **二维码扫码登录**（基于原生 CoreImage 生成二维码）
  - 两步验证（2FA）云端密码 & 新用户注册
- **原生 macOS 三栏式 / 双栏式体验**
  - `NavigationSplitView` 会话列表 + 聊天详情
  - 严格遵循 TDLib `(order, chat.id)` 排序规则，支持置顶、未读计数、全部对话 / 自定义聊天文件夹 Tabs（`updateChatFolders` + `ChatListFolder`）/ 已归档切换
  - 聊天文件夹完整交互：实时同步文件夹顺序与各文件夹未读角标、文件夹标签（`areTagsEnabled`）、`⌥⌘[` / `⌥⌘]` 快捷键切换、右键一键全部标为已读 / 添加或移出对话、新建 / 编辑 / 排序 / 删除文件夹管理面板
  - 本地 + 远端会话搜索（快捷键 `⌘K`）
  - 头像与图片消息按需下载 + `NSCache` 缓存
- **完整多媒体消息收发**
  - **接收与内联展示**：图片（模糊缩略图占位 + 渐进加载 + 剧透点击展开）、多图/视频相册网格分组、视频卡片、圆形视频消息（Video Note）、GIF/MP4 动图内联循环播放、文件卡片（类型图标 + 实时下载/上传进度与取消）、WebP 静态贴纸 / **TGS Lottie 矢量动态贴纸**（`Compression` 框架 Gzip 解压 + `Lottie` Core Animation 渲染）/ **WebM 视频贴纸**（纯 Swift EBML 解复用 + `VideoToolbox` VP9 与 Alpha 透明通道原生合成）、动态大 Emoji、位置与联系人卡片
  - **贴纸与 Emoji 表情选择器面板**：输入框原生 macOS Popover 面板支持双语搜索 Unicode Emoji（本地分类 + TDLib `searchEmojis` + 最近使用持久化）、收藏 / 最近 / 已安装 / 热门贴纸包浏览与悬停实时动画预览、输入单个 Emoji 自动弹出贴纸建议条、点击聊天中贴纸查看与一键添加/移除贴纸包
  - **语音与音频播放**：内建零依赖纯 Swift OGG/Opus → Apple CAF 容器重封装器，支持直接播放 Telegram 语音消息、可点击拖拽的 5-bit 波形进度条、音乐封面展示及 `1x / 1.5x / 2x` 倍速切换
  - **语音录制与多媒体发送**：支持麦克风录制语音消息并生成波形；支持选择器、`Finder` 拖拽、`⌘V` 粘贴剪贴板图片/文件、多附件暂存条、自动相册打包（`sendMessageAlbum`）、「以原文件发送」与「剧透模糊」开关
  - **原生 macOS 预览与导出**：内置媒体灯箱（图片缩放、`AVKit` 视频播放、`←`/`→` 切换）、系统 `Quick Look` 预览、复制图片、另存为（`NSSavePanel`）与「在 Finder 中显示」
- **现代 SwiftUI (macOS 15+) 消息时间线与富文本交互**
  - 使用 `ScrollPosition` + `.defaultScrollAnchor(.bottom)` + `.onScrollGeometryChange` 实现底部锚定、上滑自动分页加载历史消息与「回到底部」悬浮按钮
  - 完整解析 `FormattedText.entities`（UTF-16 精确映射）：粗体、斜体、下划线、删除线、行内代码、带语言标签与一键复制的代码块卡片、引用块、可点击链接、剧透点击展开、`@提及` / 用户提及直达对话
  - 完整消息交互：消息回复（`InputMessageReplyTo`、引用预览条与点击跳转高亮原消息）、消息编辑（`editMessageText` / `editMessageCaption`）、按 TDLib 权限区分仅自己/双向撤回的删除确认（`deleteMessages`）、支持搜索与多目标/隐藏来源/附言的转发弹窗（`forwardMessages`）及多选批量操作
  - 实时收发文本与多媒体消息、已编辑标记、发送中 / 已读状态回执、悬浮快捷操作与右键菜单
  - 原生 macOS `Settings` 窗口（`⌘,`）、媒体缓存清理与优雅退出清理 TDLib 数据库

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

### 方式三：直接下载 GitHub Actions 自动打包的 `.app`

每次推送到 `main` 分支后，GitHub Actions（`macos-15-intel`）会自动构建 Release 版 `SwiftUITelegram.app` 并上传为构建产物 `SwiftUITelegram-macOS-x86_64.zip`。

下载并解压后，由于 CI 产物采用 Ad-hoc 签名（未经过 Apple 公证），首次启动前需移除 macOS 隔离属性：

```bash
xattr -dr com.apple.quarantine SwiftUITelegram.app
open SwiftUITelegram.app
```

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