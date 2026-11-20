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
│  ChatListView / ConversationView / SettingsView             │
└──────────────────────────────▲──────────────────────────────┘
                               │ @Environment(AppStore.self)
┌──────────────────────────────┴──────────────────────────────┐
│                 Stores (@MainActor @Observable)             │
│  AppStore  ──┬── ChatListStore (排序/筛选/搜索/用户缓存)     │
│              ├── ConversationStore (分页/发送/已读/实时更新)  │
│              └── FileCacheStore (按需下载/NSImage 缓存)      │
└──────────────────────────────▲──────────────────────────────┘
                               │ AsyncStream<Update> + async API
┌──────────────────────────────┴──────────────────────────────┐
│                 Core Layer (TDLib + Models)                 │
│  TDLibService (唯一 TDLibClientManager + 串行更新转发)        │
│  Domain Models: ChatSummary / MessageItem / UserSummary     │
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

## 3. TDLib 集成关键细节（已在脚手架内处理）

1. **全局单 `TDLibClientManager` 实例**：TDLib 底层 `td_receive` 只允许在单一线程轮询。`TDLibService` 全局持有一个 `TDLibClientManager`，通过 `AsyncStream<Update>` 严格保序地将更新派发到 `@MainActor`。
2. **退出应用时优雅关闭**：`AppDelegate.applicationWillTerminate` 调用 `AppStore.shutdown()` -> `manager.closeClients()`，等待 TDLib 返回 `authorizationStateClosed`，避免 `⌘Q` 强杀导致本地 SQLite 数据库损坏。
3. **退出登录后重建 Client**：收到 `authorizationStateClosed` 后，旧 `TDLibClient` 会被 `TDLibClientManager` 移除；`AppStore` 会清空所有内存 Store 并自动调用 `service.startClient()` 创建新客户端，无需重启应用即可切换账号。
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
- [ ] 支持图片/文件拖拽与选取发送（`InputMessagePhoto` / `InputMessageDocument`）
- [ ] 图片灯箱预览与 `QuickLook` 集成（macOS 原生体验）
- [ ] 聊天文件夹 Tabs（`updateChatFolders` + `ChatListFolder`）

### Phase 3 — 桌面端深度体验优化
- [ ] 真正的多窗口支持（双击会话在新 macOS 窗口中独立打开）
- [ ] 语音消息播放与波形显示、贴纸（WebP / TGS Lottie / WebM）与 Emoji 表情面板
- [ ] 草稿云端同步（`setChatDraftMessage` + `updateChatDraftMessage`）
- [ ] macOS 系统通知（`UNUserNotificationCenter`）与 Dock 未读角标（`NSApp.dockTile.badgeLabel`）
- [ ] 代理配置面板（MTProxy / SOCKS5 / HTTP，`addProxy` / `enableProxy`）
- [ ] 凭证迁移至 macOS Keychain + 数据库加密密钥（`databaseEncryptionKey`）

### Phase 4 — 性能与可维护性
- [ ] 超长会话列表虚拟化与内存回收基准测试（Instruments）
- [ ] 拆分 `TelegramCore` 为独立本地 Swift Package，补充 Mock `TDLibService` 协议与 Swift Testing 单元测试
