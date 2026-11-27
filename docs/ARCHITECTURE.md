# SwiftUITelegram 架构设计与路线图（macOS 15+）

本文档记录 `SwiftUITelegram` 的技术选型、分层架构、TDLib 关键踩坑处理，以及后续迭代路线图。

---

## 1. 技术选型总览

| 模块 | 选型 | 理由 |
| --- | --- | --- |
| 目标平台 | **macOS 15.0+ (Sequoia)** | 直接使用 `ScrollPosition`、`onScrollGeometryChange`、`defaultScrollAnchor(.bottom)`、`@Observable`、`NavigationSplitView`、`SettingsLink` 等最新原生 SwiftUI API |
| Telegram 核心 | **TDLib 1.8.70 via [`Swiftgram/TDLibKit`](https://github.com/Swiftgram/TDLibKit)** | SPM 零配置引入预编译 `TDLibFramework` XCFramework；覆盖完整 MTProto 加密、断线重连、多数据中心切换、本地 SQLite 缓存与文件分片下载 |
| 状态管理 | **`@MainActor @Observable` + `AsyncStream`** | 无第三方状态库依赖，按字段粒度触发 SwiftUI 刷新，与 Swift Concurrency 自然融合 |
| 工程组织 | **`Package.swift` + XcodeGen (`project.yml`)** | 既可用 Xcode 16 直接打开 `Package.swift` 快速运行，也可用 `xcodegen generate` 生成带 App Sandbox、Entitlements、`Info.plist` 的完整 `.app` 工程 |

---

## 2. 分层架构

```
┌─────────────────────────────────────────────────────────────┐
│                   Features (SwiftUI Views)                  │
│  RootView -> AuthFlowView / MainSplitView                   │
│  ChatListView (AccountSwitcher) / ConversationView / Settings│
└──────────────────────────────▲──────────────────────────────┘
                               │ @Environment(AppStore.self)
┌──────────────────────────────┴──────────────────────────────┐
│                 Stores (@MainActor @Observable)             │
│  AppStore (多账号协调 + AudioPlaybackManager)                │
│    └── [AccountSession] (每账号独立隔离的运行时容器)          │
│         ├── ChatListStore (排序/筛选/搜索/用户缓存)           │
│         ├── ConversationStore (分页/发送/相册/已读/实时更新)  │
│         └── FileCacheStore (独立 fileId 命名空间与进度缓存)   │
└──────────────────────────────▲──────────────────────────────┘
                               │ Per-Account AsyncStream<Update>
┌──────────────────────────────┴──────────────────────────────┐
│                 Core Layer (TDLib + Models)                 │
│  TDLibClientHub (全局单 TDLibClientManager 多客户端路由)     │
│  TDLibService (每账号独立 TDLibClient + 独立 db/files 目录)  │
│  Domain Models: StoredAccountProfile / ChatSummary / Message │
└──────────────────────────────▲──────────────────────────────┘
                               │ C ABI / JSON DTO
┌──────────────────────────────┴──────────────────────────────┐
│                 TDLibKit -> TDLibFramework                  │
└─────────────────────────────────────────────────────────────┘
```

### 为什么在 Store 边界做 Model 映射（`ChatSummary` / `MessageItem`）？
1. **规避不可变大结构体拷贝成本**：TDLibKit 自动生成的 `Chat` / `Message` 有 40+ 个 `let` 字段，收到 `updateChatTitle` 或 `updateChatReadInbox` 时如果直接重建整个结构体既繁琐又脆弱。映射为轻量的可变领域模型后，增量更新只需修改单个字段。
2. **解耦上游协议变更**：TDLib 版本升级时仅需调整 `Core/Models/` 映射层，SwiftUI 视图层无需大面积改动。
3. **支持极速 `#Preview` 与单元测试**：视图完全依赖纯 Swift 值类型，不直接耦合 C++ 二进制运行时。

---

## 3. TDLib 集成关键细节（已在工程内处理）

1. **全局单 `TDLibClientManager` 多账号并发路由（`TDLibClientHub`）**：TDLib 底层 `td_receive` 只允许在单一线程轮询。`TDLibClientHub` 全局持有一个 `TDLibClientManager`，为每个 `AccountSession` 创建独立 `TDLibClient` 并隔离各自的 `db`/`files` 目录和 `FileCacheStore`（彻底避免跨账号 `fileId` 冲突）。默认槽位兼容旧版 `tdlib/db` 路径，升级无需重新登录。
2. **退出应用时优雅关闭**：`AppDelegate.applicationWillTerminate` 调用 `AppStore.shutdown()` -> `hub.closeAllClients()`，等待所有在线账号的 TDLib 客户端返回 `authorizationStateClosed`，避免 `⌘Q` 强杀导致本地 SQLite 数据库损坏。
3. **单账号独立退出 / 重建与防重复登录**：多账号模式下退出或取消添加单个账号仅调用该客户端的 `logOut()` / `close()`，并在收到 `authorizationStateClosed` 后清理独立目录，不影响其余在线账号；若新登录账号与已有活跃账号 `userId` 重复则自动切换并安全退出冗余会话。
4. **会话列表严格按 `(order, chat.id)` 降序排列**：严格遵循 TDLib `ChatPosition` 规范——仅展示 `order != 0` 的会话，排序时先比较 `order`，再比较 `chat.id`，天然支持置顶会话与实时重排。
5. **正确处理 `loadChats` 的 404 错误**：TDLib 在会话列表全部加载完成时会抛出 code `404`，`ChatListStore` 将其识别为 `hasReachedEnd = true`，不会弹出误报。
6. **首屏消息二次拉取补齐**：TDLib 首次 `getChatHistory` 常只返回本地缓存的 1 条 `lastMessage`；`ConversationStore` 在首批条数 `< 15` 时会自动以最旧消息 ID 再拉一页，确保打开会话立即填满窗口。
7. **遵循 Error 406 规则**：按 TDLib 文档要求，`TDLibErrorHelper` 屏蔽错误码 `406`，不向用户展示其内部消息。
8. **中文输入法（IME）友好发送**：`MessageComposerView` 使用原生 `TextField(..., axis: .vertical)` 配合 `.onSubmit`，避免 `.onKeyPress(.return)` 截断拼音选词回车；同时支持 `Option+Enter` 换行。

---

## 4. 后续迭代路线图

### Phase 2 — 富文本、回复与媒体收发
- [ ] 将 `FormattedText.entities` 解析为 `AttributedString`（粗体、斜体、代码块、链接、剧透、@提及）
- [ ] 支持消息回复（`InputMessageReplyTo`）、编辑（`editMessageText`）、删除（`deleteMessages`）与转发
- [x] 支持图片/视频/GIF/音频/文件选取、拖拽、剪贴板 `⌘V` 粘贴与多图相册发送（`InputMessagePhoto` / `InputMessageVideo` / `InputMessageAnimation` / `InputMessageAudio` / `InputMessageDocument` / `sendMessageAlbum`）
- [x] 图片/视频/GIF 灯箱预览（缩放、键盘切换、`AVKit` 播放）与 `QuickLook` 集成（macOS 原生体验）
- [x] 语音消息录制（`AVAudioRecorder` + 5-bit 波形编码）与 OGG/Opus 原生播放（零依赖 OGG → Apple CAF 无损重封装 + 波形进度拖拽 + 倍速播放）
- [x] 圆形视频消息（Video Note）、动态 GIF 内联循环播放、贴纸展示、文件下载/上传进度与取消控制、另存为 / Finder 定位
- [ ] 聊天文件夹 Tabs（`updateChatFolders` + `ChatListFolder`）

### Phase 3 — 桌面端深度体验优化
- [ ] 真正的多窗口支持（双击会话在新 macOS 窗口中独立打开）
- [ ] 贴纸动画渲染（TGS Lottie / WebM）与贴纸 / Emoji 表情选择器面板
- [ ] 草稿云端同步（`setChatDraftMessage` + `updateChatDraftMessage`）
- [ ] macOS 系统通知（`UNUserNotificationCenter`）与 Dock 未读角标（`NSApp.dockTile.badgeLabel`）
- [ ] 代理配置面板（MTProxy / SOCKS5 / HTTP，`addProxy` / `enableProxy`）
- [ ] 凭证迁移至 macOS Keychain + 数据库加密密钥（`databaseEncryptionKey`）

### Phase 4 — 性能与可维护性
- [ ] 超长会话列表虚拟化与内存回收基准测试（Instruments）
- [ ] 拆分 `TelegramCore` 为独立本地 Swift Package，补充 Mock `TDLibService` 协议与 Swift Testing 单元测试
