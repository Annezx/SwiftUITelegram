import Foundation
import TDLibKit

/// Domain model representing a Telegram sticker across picker grids, sticker packs,
/// favorites, recents, and search results.
struct StickerItem: Identifiable, Equatable, Hashable, Sendable {
    let stickerId: Int64
    let setId: Int64
    let emoji: String
    let width: Int
    let height: Int
    let format: StickerMediaFormat
    let file: MediaFileDescriptor
    let remoteFileId: String
    let remoteUniqueId: String
    let thumbnail: ThumbnailInfo?
    let isPremium: Bool

    var id: String {
        if !remoteUniqueId.isEmpty {
            return "\(remoteUniqueId)-\(file.fileId)"
        }
        return "\(setId)-\(stickerId)-\(file.fileId)"
    }

    var asStickerMedia: StickerMedia {
        StickerMedia(
            stickerId: stickerId,
            setId: setId,
            file: file,
            remoteFileId: remoteFileId,
            thumbnail: thumbnail,
            emoji: emoji,
            width: width,
            height: height,
            format: format,
            isAnimatedEmoji: false
        )
    }

    init(
        stickerId: Int64,
        setId: Int64,
        emoji: String,
        width: Int,
        height: Int,
        format: StickerMediaFormat,
        file: MediaFileDescriptor,
        remoteFileId: String = "",
        remoteUniqueId: String = "",
        thumbnail: ThumbnailInfo? = nil,
        isPremium: Bool = false
    ) {
        self.stickerId = stickerId
        self.setId = setId
        self.emoji = emoji
        self.width = width
        self.height = height
        self.format = format
        self.file = file
        self.remoteFileId = remoteFileId
        self.remoteUniqueId = remoteUniqueId
        self.thumbnail = thumbnail
        self.isPremium = isPremium
    }

    init(tdSticker: Sticker) {
        self.stickerId = tdSticker.id.rawValue
        self.setId = tdSticker.setId.rawValue
        self.emoji = tdSticker.emoji
        self.width = tdSticker.width
        self.height = tdSticker.height
        self.format = StickerMediaFormat(tdFormat: tdSticker.format)
        self.file = MediaFileDescriptor(tdFile: tdSticker.sticker)
        self.remoteFileId = tdSticker.sticker.remote.id
        self.remoteUniqueId = tdSticker.sticker.remote.uniqueId
        self.thumbnail = tdSticker.thumbnail.map(ThumbnailInfo.init(tdThumbnail:))
        if case .stickerFullTypeRegular(let regular) = tdSticker.fullType {
            self.isPremium = regular.premiumAnimation != nil
        } else {
            self.isPremium = false
        }
    }
}

/// Lightweight summary of an installed, trending, or searched sticker pack (`StickerSetInfo`).
struct StickerPackSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: Int64
    let title: String
    let name: String
    let size: Int
    var isInstalled: Bool
    var isArchived: Bool
    let isOfficial: Bool
    let thumbnail: ThumbnailInfo?
    let covers: [StickerItem]

    /// Preferred sticker/thumbnail descriptor used for rendering this pack's icon in tabs.
    var iconSticker: StickerItem? {
        covers.first
    }

    init(
        id: Int64,
        title: String,
        name: String,
        size: Int,
        isInstalled: Bool,
        isArchived: Bool,
        isOfficial: Bool,
        thumbnail: ThumbnailInfo?,
        covers: [StickerItem]
    ) {
        self.id = id
        self.title = title
        self.name = name
        self.size = size
        self.isInstalled = isInstalled
        self.isArchived = isArchived
        self.isOfficial = isOfficial
        self.thumbnail = thumbnail
        self.covers = covers
    }

    init(tdInfo: StickerSetInfo) {
        self.id = tdInfo.id.rawValue
        self.title = tdInfo.title
        self.name = tdInfo.name
        self.size = tdInfo.size
        self.isInstalled = tdInfo.isInstalled
        self.isArchived = tdInfo.isArchived
        self.isOfficial = tdInfo.isOfficial
        self.thumbnail = tdInfo.thumbnail.map(ThumbnailInfo.init(tdThumbnail:))
        self.covers = tdInfo.covers.map(StickerItem.init(tdSticker:))
    }

    init(from detail: StickerPackDetail) {
        self.id = detail.id
        self.title = detail.title
        self.name = detail.name
        self.size = detail.stickers.count
        self.isInstalled = detail.isInstalled
        self.isArchived = detail.isArchived
        self.isOfficial = detail.isOfficial
        self.thumbnail = detail.thumbnail
        self.covers = Array(detail.stickers.prefix(5))
    }
}

/// Full sticker pack metadata and sticker items (`StickerSet`).
struct StickerPackDetail: Identifiable, Equatable, Hashable, Sendable {
    let id: Int64
    let title: String
    let name: String
    var isInstalled: Bool
    var isArchived: Bool
    let isOfficial: Bool
    let thumbnail: ThumbnailInfo?
    let stickers: [StickerItem]

    var formatSummary: String? {
        if stickers.contains(where: { $0.format == .tgs }) {
            return "动态贴纸"
        }
        if stickers.contains(where: { $0.format == .webm }) {
            return "视频贴纸"
        }
        return nil
    }

    init(
        id: Int64,
        title: String,
        name: String,
        isInstalled: Bool,
        isArchived: Bool,
        isOfficial: Bool,
        thumbnail: ThumbnailInfo?,
        stickers: [StickerItem]
    ) {
        self.id = id
        self.title = title
        self.name = name
        self.isInstalled = isInstalled
        self.isArchived = isArchived
        self.isOfficial = isOfficial
        self.thumbnail = thumbnail
        self.stickers = stickers
    }

    init(tdSet: StickerSet) {
        self.id = tdSet.id.rawValue
        self.title = tdSet.title
        self.name = tdSet.name
        self.isInstalled = tdSet.isInstalled
        self.isArchived = tdSet.isArchived
        self.isOfficial = tdSet.isOfficial
        self.thumbnail = tdSet.thumbnail.map(ThumbnailInfo.init(tdThumbnail:))
        self.stickers = tdSet.stickers.map(StickerItem.init(tdSticker:))
    }
}

/// Identifiable sheet payload for opening a sticker pack preview & install modal.
struct StickerPackSheetRequest: Identifiable, Equatable, Hashable, Sendable {
    let id: Int64

    var setId: Int64 { id }
}

// MARK: - Emoji Picker Catalog

struct EmojiEntry: Identifiable, Equatable, Hashable, Sendable {
    let symbol: String
    let label: String
    let keywords: String

    var id: String { symbol }

    init(_ symbol: String, _ label: String, _ keywords: String = "") {
        self.symbol = symbol
        self.label = label
        self.keywords = "\(label) \(keywords)".lowercased()
    }
}

enum EmojiCategoryKind: String, CaseIterable, Identifiable, Sendable {
    case recent
    case smileys
    case gestures
    case animals
    case food
    case activities
    case travel
    case objects
    case symbols

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "最近使用"
        case .smileys: return "笑脸与情感"
        case .gestures: return "手势与人物"
        case .animals: return "动物与自然"
        case .food: return "美食与饮品"
        case .activities: return "活动与运动"
        case .travel: return "旅行与地点"
        case .objects: return "常用物品"
        case .symbols: return "符号与标记"
        }
    }

    var systemImage: String {
        switch self {
        case .recent: return "clock"
        case .smileys: return "face.smiling"
        case .gestures: return "hand.raised"
        case .animals: return "pawprint"
        case .food: return "cup.and.saucer"
        case .activities: return "sportscourt"
        case .travel: return "airplane"
        case .objects: return "lightbulb"
        case .symbols: return "heart"
        }
    }
}

struct EmojiCategorySection: Identifiable, Sendable {
    let kind: EmojiCategoryKind
    let entries: [EmojiEntry]

    var id: EmojiCategoryKind { kind }
    var title: String { kind.title }
}

/// Curated Unicode Emoji catalog with bilingual (Chinese & English) search metadata.
enum EmojiCatalog {
    static let sections: [EmojiCategorySection] = [
        EmojiCategorySection(kind: .smileys, entries: [
            EmojiEntry("😀", "笑脸", "grinning smile happy 开心 微笑"),
            EmojiEntry("😃", "大笑", "smiley happy 开心 笑"),
            EmojiEntry("😄", "哈哈笑", "smile happy laugh 笑 哈哈"),
            EmojiEntry("😁", "露齿笑", "grin beam 嘻嘻"),
            EmojiEntry("😆", "眯眼大笑", "laughing xd 哈哈 爆笑"),
            EmojiEntry("😅", "苦笑", "sweat smile 尴尬 擦汗"),
            EmojiEntry("🤣", "笑得满地打滚", "rofl lol 笑死 哈哈"),
            EmojiEntry("😂", "笑哭", "joy tears laugh 破涕为笑 哈哈"),
            EmojiEntry("🙂", "微笑", "slightly smiling 微笑 呵"),
            EmojiEntry("🙃", "倒笑脸", "upside down 无语 呵呵"),
            EmojiEntry("😉", "眨眼", "wink 抛媚眼 眨眼"),
            EmojiEntry("😊", "害羞微笑", "blush shy 害羞 开心"),
            EmojiEntry("😇", "天使", "innocent angel 乖 善良"),
            EmojiEntry("🥰", "爱心笑脸", "smiling hearts love 喜欢 爱"),
            EmojiEntry("😍", "花痴", "heart eyes love 喜欢 爱慕"),
            EmojiEntry("🤩", "星星眼", "star struck 崇拜 惊艳"),
            EmojiEntry("😘", "飞吻", "kiss heart 亲亲 么么哒"),
            EmojiEntry("😗", "亲亲", "kissing 亲"),
            EmojiEntry("😚", "闭眼亲", "kissing closed eyes 亲亲"),
            EmojiEntry("😋", "美味", "yum delicious 馋 好吃"),
            EmojiEntry("😛", "吐舌", "stuck out tongue 调皮"),
            EmojiEntry("😜", "眨眼吐舌", "wink tongue 调皮 搞怪"),
            EmojiEntry("🤪", "滑稽", "zany crazy 滑稽 沙雕"),
            EmojiEntry("😝", "眯眼吐舌", "squinting tongue 调皮"),
            EmojiEntry("🤑", "发财", "money mouth rich 钱 财迷"),
            EmojiEntry("🤗", "抱抱", "hugging hug 拥抱 抱抱"),
            EmojiEntry("🤭", "捂嘴笑", "hand over mouth 偷笑 害羞"),
            EmojiEntry("🤫", "嘘", "shushing quiet 安静 保密"),
            EmojiEntry("🤔", "思考", "thinking hmm 思考 沉思"),
            EmojiEntry("🤐", "闭嘴", "zipper mouth 闭嘴 保密"),
            EmojiEntry("🤨", "挑眉", "raised eyebrow 怀疑 疑惑"),
            EmojiEntry("😐", "面无表情", "neutral 无语 淡定"),
            EmojiEntry("😑", "无语", "expressionless 无语 呆"),
            EmojiEntry("😶", "沉默", "no mouth 沉默 无言"),
            EmojiEntry("😏", "得意", "smirk 坏笑 得意"),
            EmojiEntry("😒", "斜眼", "unamused 嫌弃 白眼"),
            EmojiEntry("🙄", "翻白眼", "eye roll 无语 白眼"),
            EmojiEntry("😬", "龇牙", "grimacing 尴尬 紧张"),
            EmojiEntry("🤥", "说谎", "lying pinocchio 骗人"),
            EmojiEntry("😌", "松口气", "relieved 安心 满足"),
            EmojiEntry("😔", "失落", "pensive 难过 低落"),
            EmojiEntry("😪", "困", "sleepy 困倦 打瞌睡"),
            EmojiEntry("🤤", "流口水", "drooling 馋 口水"),
            EmojiEntry("😴", "睡觉", "sleeping zzz 晚安 睡觉"),
            EmojiEntry("😷", "口罩", "mask sick 生病 感冒"),
            EmojiEntry("🤒", "发烧", "thermometer fever 生病"),
            EmojiEntry("🤕", "受伤", "bandage hurt 受伤"),
            EmojiEntry("🤢", "恶心", "nauseated sick 想吐"),
            EmojiEntry("🤮", "呕吐", "vomiting puke 吐了"),
            EmojiEntry("🤧", "打喷嚏", "sneezing cold 感冒"),
            EmojiEntry("🥵", "热", "hot sweat 炎热 脸红"),
            EmojiEntry("🥶", "冷", "cold freezing 冻死了"),
            EmojiEntry("🥴", "晕乎乎", "woozy drunk 晕 醉"),
            EmojiEntry("😵", "眩晕", "dizzy 晕倒"),
            EmojiEntry("🤯", "震惊", "exploding head mind blown 炸裂 震惊"),
            EmojiEntry("🤠", "牛仔", "cowboy 酷"),
            EmojiEntry("🥳", "庆祝", "partying celebrate 派对 生日快乐"),
            EmojiEntry("🥸", "伪装", "disguised 假装"),
            EmojiEntry("😎", "墨镜酷", "sunglasses cool 酷 墨镜 帅"),
            EmojiEntry("🤓", "书呆子", "nerd glasses 眼镜 学霸"),
            EmojiEntry("🧐", "单片眼镜", "monocle inspect 审视 观察"),
            EmojiEntry("😕", "困惑", "confused 纠结"),
            EmojiEntry("😟", "担心", "worried 担忧"),
            EmojiEntry("🙁", "不开心", "frowning 委屈"),
            EmojiEntry("😮", "惊讶", "open mouth wow 哇 惊讶"),
            EmojiEntry("😯", "吃惊", "hushed 惊讶"),
            EmojiEntry("😲", "震惊", "astonished shocked 吃惊"),
            EmojiEntry("😳", "脸红惊讶", "flushed embarrassed 害羞 惊呆"),
            EmojiEntry("🥺", "恳求", "pleading puppy eyes 可怜 拜托"),
            EmojiEntry("🥹", "感动落泪", "holding back tears 感动 泪目"),
            EmojiEntry("😦", "呆住", "frowning open mouth 啊"),
            EmojiEntry("😧", "痛苦", "anguished 难受"),
            EmojiEntry("😨", "害怕", "fearful scared 恐惧"),
            EmojiEntry("😰", "冷汗", "anxious sweat 紧张 焦虑"),
            EmojiEntry("😥", "伤心擦汗", "sad relieved 失望"),
            EmojiEntry("😢", "流泪", "cry sad 哭 难过"),
            EmojiEntry("😭", "大哭", "sob crying 哭泣 呜呜 暴哭"),
            EmojiEntry("😱", "吓死了", "scream fear 尖叫 恐怖"),
            EmojiEntry("😖", "纠结", "confounded 郁闷"),
            EmojiEntry("😣", "忍耐", "persevere 难受"),
            EmojiEntry("😞", "失望", "disappointed 难过"),
            EmojiEntry("😓", "汗", "downcast sweat 辛苦"),
            EmojiEntry("😩", "疲惫", "weary tired 累死了"),
            EmojiEntry("😫", "崩溃", "tired exhausted 崩溃"),
            EmojiEntry("🥱", "打哈欠", "yawning sleepy 困 无聊"),
            EmojiEntry("😤", "生气哼", "triumph huff 哼 生气"),
            EmojiEntry("😡", "愤怒", "rage angry 气死了 怒"),
            EmojiEntry("😠", "生气", "angry mad 不爽"),
            EmojiEntry("🤬", "骂人", "cursing swearing 脏话 暴怒"),
            EmojiEntry("😈", "坏笑恶魔", "smiling imp devil 邪恶"),
            EmojiEntry("👿", "生气恶魔", "imp angry devil 恶魔"),
            EmojiEntry("💀", "骷髅", "skull dead 死 笑死"),
            EmojiEntry("💩", "便便", "poop shit 屎"),
            EmojiEntry("🤡", "小丑", "clown 小丑 竟是我自己"),
            EmojiEntry("👻", "幽灵", "ghost boo 鬼"),
            EmojiEntry("👽", "外星人", "alien ufo"),
            EmojiEntry("🤖", "机器人", "robot bot ai"),
            EmojiEntry("😺", "开心猫", "cat smile 猫咪"),
            EmojiEntry("😸", "大笑猫", "cat grin 猫"),
            EmojiEntry("😹", "笑哭猫", "cat joy 猫"),
            EmojiEntry("😻", "花痴猫", "cat heart eyes 猫"),
            EmojiEntry("🙀", "震惊猫", "cat weary 猫"),
            EmojiEntry("🙈", "非礼勿视", "see no evil monkey 捂眼 害羞"),
            EmojiEntry("🙉", "非礼勿听", "hear no evil monkey"),
            EmojiEntry("🙊", "非礼勿言", "speak no evil monkey 捂嘴")
        ]),
        EmojiCategorySection(kind: .gestures, entries: [
            EmojiEntry("👋", "挥手", "wave hello hi bye 你好 再见 拜拜"),
            EmojiEntry("🤚", "举手背", "raised back hand"),
            EmojiEntry("✋", "停止举手", "raised hand stop 停 嗨"),
            EmojiEntry("🖖", "瓦肯举手礼", "vulcan salute"),
            EmojiEntry("👌", "OK", "ok hand 好的 没问题 可以"),
            EmojiEntry("🤌", "捏手指", "pinched fingers 意大利"),
            EmojiEntry("🤏", "一点点", "pinching hand 一点点 小"),
            EmojiEntry("✌️", "耶", "victory peace v 胜利 耶"),
            EmojiEntry("🤞", "祝好运", "crossed fingers luck 好运 祈祷"),
            EmojiEntry("🤟", "爱你手势", "love you gesture"),
            EmojiEntry("🤘", "摇滚", "rock on metal 摇滚"),
            EmojiEntry("🤙", "打电话", "call me shaka 666"),
            EmojiEntry("👈", "向左指", "point left 左"),
            EmojiEntry("👉", "向右指", "point right 右"),
            EmojiEntry("👆", "向上指", "point up 上"),
            EmojiEntry("👇", "向下指", "point down 下"),
            EmojiEntry("☝️", "食指向上", "index pointing up 注意 第一"),
            EmojiEntry("👍", "点赞", "thumbs up good like 赞 厉害 棒 好的"),
            EmojiEntry("👎", "踩", "thumbs down bad 差 不行"),
            EmojiEntry("✊", "握拳", "raised fist 加油 必胜"),
            EmojiEntry("👊", "出拳", "oncoming fist 碰拳"),
            EmojiEntry("👏", "鼓掌", "clap applause 鼓掌 啪啪啪 牛"),
            EmojiEntry("🙌", "欢呼举手", "raising hands hooray 万岁 耶"),
            EmojiEntry("🫶", "比心", "heart hands love 比心 爱"),
            EmojiEntry("👐", "张开双手", "open hands"),
            EmojiEntry("🤲", "捧起", "palms up"),
            EmojiEntry("🤝", "握手", "handshake deal 合作 成交"),
            EmojiEntry("🙏", "祈祷感谢", "pray please thanks 谢谢 拜托 感恩"),
            EmojiEntry("✍️", "写字", "writing hand 记录"),
            EmojiEntry("💪", "肌肉加油", "muscle strong 加油 强 健身"),
            EmojiEntry("👀", "看", "eyes look watch 围观 看看 吃瓜"),
            EmojiEntry("👁️", "眼睛", "eye 看"),
            EmojiEntry("🧠", "大脑", "brain smart 聪明 思考"),
            EmojiEntry("❤️‍🔥", "炽热之心", "heart on fire 热爱 燃"),
            EmojiEntry("💋", "唇印", "kiss mark 吻"),
            EmojiEntry("👤", "人像", "silhouette user 用户"),
            EmojiEntry("👥", "多人", "people group 群组"),
            EmojiEntry("🫂", "拥抱", "people hugging 抱抱"),
            EmojiEntry("🤦", "捂脸", "facepalm 无语 扶额"),
            EmojiEntry("🤷", "摊手", "shrug 无奈 不知道"),
            EmojiEntry("🙋", "举手", "raising hand 提问 我来"),
            EmojiEntry("🙇", "鞠躬道歉", "bow sorry thanks 抱歉 感谢"),
            EmojiEntry("🧑‍💻", "程序员", "technologist coder developer 开发 写代码"),
            EmojiEntry("🧑‍🎨", "设计师", "artist designer 画画"),
            EmojiEntry("🏃", "跑步", "running 跑 冲"),
            EmojiEntry("💃", "跳舞", "dancer party 开心")
        ]),
        EmojiCategorySection(kind: .animals, entries: [
            EmojiEntry("🐶", "小狗", "dog puppy 狗 旺财"),
            EmojiEntry("🐱", "小猫", "cat kitty 猫 喵"),
            EmojiEntry("🐭", "老鼠", "mouse 鼠"),
            EmojiEntry("🐹", "仓鼠", "hamster 仓鼠"),
            EmojiEntry("🐰", "兔子", "rabbit bunny 兔"),
            EmojiEntry("🦊", "狐狸", "fox 狐狸"),
            EmojiEntry("🐻", "熊", "bear 熊"),
            EmojiEntry("🐼", "熊猫", "panda 国宝 熊猫"),
            EmojiEntry("🐨", "考拉", "koala 考拉"),
            EmojiEntry("🐯", "老虎", "tiger 虎"),
            EmojiEntry("🦁", "狮子", "lion 狮"),
            EmojiEntry("🐮", "奶牛", "cow 牛"),
            EmojiEntry("🐷", "小猪", "pig 猪"),
            EmojiEntry("🐸", "青蛙", "frog 蛙"),
            EmojiEntry("🐵", "猴子", "monkey 猴"),
            EmojiEntry("🐔", "公鸡", "chicken 鸡"),
            EmojiEntry("🐧", "企鹅", "penguin 企鹅"),
            EmojiEntry("🐦", "小鸟", "bird 鸟"),
            EmojiEntry("🦆", "鸭子", "duck 鸭"),
            EmojiEntry("🦉", "猫头鹰", "owl 夜猫子"),
            EmojiEntry("🐺", "狼", "wolf 狼"),
            EmojiEntry("🦄", "独角兽", "unicorn 独角兽"),
            EmojiEntry("🐝", "蜜蜂", "bee 蜜蜂"),
            EmojiEntry("🦋", "蝴蝶", "butterfly 蝴蝶"),
            EmojiEntry("🐢", "乌龟", "turtle 慢 龟"),
            EmojiEntry("🐍", "蛇", "snake 蛇"),
            EmojiEntry("🦖", "恐龙", "t-rex dinosaur 恐龙"),
            EmojiEntry("🐙", "章鱼", "octopus 章鱼"),
            EmojiEntry("🐬", "海豚", "dolphin 海豚"),
            EmojiEntry("🐳", "鲸鱼", "whale 鲸鱼"),
            EmojiEntry("🦈", "鲨鱼", "shark 鲨鱼"),
            EmojiEntry("🐾", "爪印", "paw prints 脚印"),
            EmojiEntry("🌸", "樱花", "cherry blossom flower 花 春天"),
            EmojiEntry("🌹", "玫瑰", "rose flower 玫瑰 浪漫"),
            EmojiEntry("🌻", "向日葵", "sunflower 阳光"),
            EmojiEntry("🍀", "四叶草", "four leaf clover lucky 幸运"),
            EmojiEntry("🌵", "仙人掌", "cactus"),
            EmojiEntry("🌲", "松树", "evergreen tree 树"),
            EmojiEntry("🍁", "枫叶", "maple leaf 秋天"),
            EmojiEntry("☀️", "太阳", "sun sunny 晴天 阳光"),
            EmojiEntry("🌙", "月亮", "moon night 晚安 月亮"),
            EmojiEntry("⭐", "星星", "star 星星 收藏"),
            EmojiEntry("🌟", "闪亮星星", "glowing star 闪亮"),
            EmojiEntry("✨", "闪耀", "sparkles magic 闪闪 亮晶晶"),
            EmojiEntry("⚡", "闪电", "zap lightning fast 闪电 快"),
            EmojiEntry("🔥", "火", "fire hot lit 火 爆 厉害 热门"),
            EmojiEntry("🌈", "彩虹", "rainbow 彩虹"),
            EmojiEntry("☁️", "云", "cloud 多云"),
            EmojiEntry("🌧️", "下雨", "rain 雨天"),
            EmojiEntry("❄️", "雪花", "snowflake winter 下雪 冷"),
            EmojiEntry("🌊", "海浪", "ocean wave 浪 海")
        ]),
        EmojiCategorySection(kind: .food, entries: [
            EmojiEntry("🍎", "苹果", "apple fruit 苹果 水果"),
            EmojiEntry("🍊", "橘子", "tangerine orange 橙子"),
            EmojiEntry("🍋", "柠檬", "lemon 酸 柠檬"),
            EmojiEntry("🍉", "西瓜", "watermelon 吃瓜 西瓜 夏天"),
            EmojiEntry("🍇", "葡萄", "grapes 葡萄"),
            EmojiEntry("🍓", "草莓", "strawberry 草莓"),
            EmojiEntry("🍒", "樱桃", "cherries 车厘子"),
            EmojiEntry("🍑", "桃子", "peach 桃子"),
            EmojiEntry("🥭", "芒果", "mango 芒果"),
            EmojiEntry("🍍", "菠萝", "pineapple 凤梨"),
            EmojiEntry("🥑", "牛油果", "avocado 牛油果"),
            EmojiEntry("🍅", "番茄", "tomato 西红柿"),
            EmojiEntry("🌶️", "辣椒", "hot pepper spicy 辣"),
            EmojiEntry("🌽", "玉米", "corn 玉米"),
            EmojiEntry("🍔", "汉堡", "hamburger burger 汉堡 快餐"),
            EmojiEntry("🍟", "薯条", "fries 薯条"),
            EmojiEntry("🍕", "披萨", "pizza 披萨"),
            EmojiEntry("🌭", "热狗", "hot dog 热狗"),
            EmojiEntry("🥪", "三明治", "sandwich 三明治"),
            EmojiEntry("🌮", "塔可", "taco"),
            EmojiEntry("🍜", "拉面", "ramen noodles 面条 泡面"),
            EmojiEntry("🍣", "寿司", "sushi 日料 寿司"),
            EmojiEntry("🍱", "便当", "bento 盒饭"),
            EmojiEntry("🥟", "饺子", "dumpling 饺子 水饺"),
            EmojiEntry("🍚", "米饭", "rice 干饭 米饭"),
            EmojiEntry("🍛", "咖喱饭", "curry 咖喱"),
            EmojiEntry("🥩", "牛排", "steak meat 肉"),
            EmojiEntry("🍗", "鸡腿", "poultry leg 加鸡腿 炸鸡"),
            EmojiEntry("🍰", "蛋糕", "cake dessert 甜品 蛋糕"),
            EmojiEntry("🎂", "生日蛋糕", "birthday cake 生日快乐"),
            EmojiEntry("🧁", "纸杯蛋糕", "cupcake 甜点"),
            EmojiEntry("🍩", "甜甜圈", "doughnut donut"),
            EmojiEntry("🍪", "饼干", "cookie 曲奇"),
            EmojiEntry("🍫", "巧克力", "chocolate 巧克力"),
            EmojiEntry("🍦", "冰淇淋", "ice cream 甜筒"),
            EmojiEntry("🧋", "珍珠奶茶", "bubble tea boba 奶茶"),
            EmojiEntry("☕", "咖啡", "coffee cafe 美式 拿铁 提神"),
            EmojiEntry("🍵", "热茶", "tea matcha 喝茶 绿茶"),
            EmojiEntry("🧃", "果汁", "beverage box 饮料"),
            EmojiEntry("🍺", "啤酒", "beer 干杯 喝酒"),
            EmojiEntry("🍻", "干杯", "clinking beers cheers 干杯 聚会"),
            EmojiEntry("🥂", "香槟干杯", "champagne cheers 庆祝 干杯"),
            EmojiEntry("🍷", "红酒", "wine 葡萄酒"),
            EmojiEntry("🍸", "鸡尾酒", "cocktail 酒吧")
        ]),
        EmojiCategorySection(kind: .activities, entries: [
            EmojiEntry("🎉", "拉花庆祝", "tada party confetti 庆祝 恭喜 撒花"),
            EmojiEntry("🎊", "彩带球", "confetti ball 恭喜 庆祝"),
            EmojiEntry("🎈", "气球", "balloon 派对 生日"),
            EmojiEntry("🎁", "礼物", "gift present 礼物 惊喜"),
            EmojiEntry("🏆", "奖杯", "trophy winner 冠军 第一 厉害"),
            EmojiEntry("🥇", "金牌", "first place medal 第一"),
            EmojiEntry("🎯", "靶心", "bullseye target 目标 精准"),
            EmojiEntry("🎮", "游戏手柄", "video game gaming 打游戏"),
            EmojiEntry("🎲", "骰子", "game die dice 运气 骰子"),
            EmojiEntry("🧩", "拼图", "puzzle 拼图"),
            EmojiEntry("🎵", "音符", "musical note music 音乐 歌"),
            EmojiEntry("🎶", "音乐", "musical notes song 听歌"),
            EmojiEntry("🎧", "耳机", "headphones music 耳机"),
            EmojiEntry("🎤", "麦克风", "microphone karaoke 唱歌 ktv"),
            EmojiEntry("🎸", "吉他", "guitar rock 吉他"),
            EmojiEntry("🎬", "电影", "clapper movie film 看电影"),
            EmojiEntry("🎨", "调色板", "palette art design 画画 艺术"),
            EmojiEntry("⚽", "足球", "soccer football 踢球"),
            EmojiEntry("🏀", "篮球", "basketball 打球"),
            EmojiEntry("🏈", "橄榄球", "american football"),
            EmojiEntry("⚾", "棒球", "baseball"),
            EmojiEntry("🎾", "网球", "tennis"),
            EmojiEntry("🏓", "乒乓球", "ping pong"),
            EmojiEntry("🏸", "羽毛球", "badminton"),
            EmojiEntry("🏊", "游泳", "swimming"),
            EmojiEntry("🚴", "骑行", "biking cycling"),
            EmojiEntry("🧘", "冥想瑜伽", "yoga meditate 放松")
        ]),
        EmojiCategorySection(kind: .travel, entries: [
            EmojiEntry("🚗", "汽车", "car drive 开车"),
            EmojiEntry("🚕", "出租车", "taxi 打车"),
            EmojiEntry("🚌", "公交车", "bus 公交"),
            EmojiEntry("🚇", "地铁", "metro subway 地铁"),
            EmojiEntry("🚄", "高铁", "bullet train 高铁 火车"),
            EmojiEntry("✈️", "飞机", "airplane flight 旅行 出差"),
            EmojiEntry("🚀", "火箭", "rocket launch fast 起飞 上线 冲"),
            EmojiEntry("🛸", "飞碟", "flying saucer ufo"),
            EmojiEntry("⛵", "帆船", "sailboat 出海"),
            EmojiEntry("🏠", "房子", "house home 家"),
            EmojiEntry("🏢", "办公楼", "office building 公司 上班"),
            EmojiEntry("🏥", "医院", "hospital 医院"),
            EmojiEntry("🏫", "学校", "school 学校"),
            EmojiEntry("🏨", "酒店", "hotel 住宿"),
            EmojiEntry("🏖️", "沙滩", "beach vacation 度假 旅游"),
            EmojiEntry("🏔️", "雪山", "mountain 爬山 风景"),
            EmojiEntry("🏕️", "露营", "camping 露营"),
            EmojiEntry("🗺️", "地图", "world map 地图 旅行"),
            EmojiEntry("🌍", "地球", "globe earth world 世界"),
            EmojiEntry("🧭", "指南针", "compass 方向")
        ]),
        EmojiCategorySection(kind: .objects, entries: [
            EmojiEntry("💻", "笔记本电脑", "laptop mac computer 电脑 写代码 工作"),
            EmojiEntry("🖥️", "台式电脑", "desktop monitor 显示器"),
            EmojiEntry("⌨️", "键盘", "keyboard 打字"),
            EmojiEntry("📱", "手机", "iphone mobile phone 手机"),
            EmojiEntry("⌚", "手表", "watch 时间"),
            EmojiEntry("📷", "相机", "camera photo 拍照 摄影"),
            EmojiEntry("📺", "电视", "tv 追剧"),
            EmojiEntry("🔋", "电池", "battery 电量 充电"),
            EmojiEntry("🔌", "插头", "electric plug"),
            EmojiEntry("💡", "灯泡灵感", "bulb idea 灵感 主意 点子"),
            EmojiEntry("🔦", "手电筒", "flashlight"),
            EmojiEntry("📚", "书本", "books study read 学习 看书 文档"),
            EmojiEntry("📝", "备忘录", "memo note 笔记 记录"),
            EmojiEntry("📅", "日历", "calendar schedule 日程 计划"),
            EmojiEntry("📌", "图钉", "pushpin pin 置顶 标记"),
            EmojiEntry("📎", "回形针", "paperclip attachment 附件"),
            EmojiEntry("🔍", "放大镜", "search magnifying glass 搜索 查找"),
            EmojiEntry("🔒", "锁", "lock secure private 加密 安全"),
            EmojiEntry("🔓", "解锁", "unlock 开放"),
            EmojiEntry("🔑", "钥匙", "key password 密钥 关键"),
            EmojiEntry("🛠️", "工具", "tools hammer wrench 维修 工具 构建"),
            EmojiEntry("⚙️", "设置齿轮", "gear settings 配置 设置"),
            EmojiEntry("🧪", "试管实验", "test tube experiment 测试 实验"),
            EmojiEntry("📦", "包裹", "package box 快递 打包 发布"),
            EmojiEntry("💰", "钱袋", "money bag rich 钱 工资 奖金"),
            EmojiEntry("💳", "信用卡", "credit card 支付 付款"),
            EmojiEntry("🧾", "小票收据", "receipt 账单"),
            EmojiEntry("✉️", "信封邮件", "envelope mail email 邮件"),
            EmojiEntry("🔔", "铃铛通知", "bell notification 提醒 通知"),
            EmojiEntry("⏰", "闹钟", "alarm clock 时间 提醒"),
            EmojiEntry("⏳", "沙漏", "hourglass waiting 等待 加载")
        ]),
        EmojiCategorySection(kind: .symbols, entries: [
            EmojiEntry("❤️", "红心", "red heart love 爱 喜欢 爱心"),
            EmojiEntry("🧡", "橙心", "orange heart 爱心"),
            EmojiEntry("💛", "黄心", "yellow heart 爱心"),
            EmojiEntry("💚", "绿心", "green heart 爱心"),
            EmojiEntry("💙", "蓝心", "blue heart 爱心"),
            EmojiEntry("💜", "紫心", "purple heart 爱心"),
            EmojiEntry("🖤", "黑心", "black heart 爱心"),
            EmojiEntry("🤍", "白心", "white heart 爱心"),
            EmojiEntry("🩷", "粉心", "pink heart 爱心"),
            EmojiEntry("💔", "心碎", "broken heart 伤心 难过"),
            EmojiEntry("💕", "双爱心", "two hearts 恋爱 喜欢"),
            EmojiEntry("💖", "闪亮爱心", "sparkling heart 心动"),
            EmojiEntry("💘", "丘比特之箭", "cupid heart 爱"),
            EmojiEntry("💯", "一百分", "100 perfect 满分 同意 必须"),
            EmojiEntry("💢", "怒气", "anger 生气"),
            EmojiEntry("💥", "爆炸", "boom collision 炸裂 厉害"),
            EmojiEntry("💫", "头晕星星", "dizzy 晕 闪耀"),
            EmojiEntry("💦", "汗滴", "sweat droplets 汗 紧张"),
            EmojiEntry("💤", "睡觉符号", "zzz sleep 困 晚安"),
            EmojiEntry("💬", "对话气泡", "speech balloon chat 聊天 评论"),
            EmojiEntry("💭", "思考气泡", "thought balloon 想法"),
            EmojiEntry("✅", "完成勾选", "check mark done ok 完成 可以 没问题"),
            EmojiEntry("❌", "叉号错误", "cross mark wrong no 错 不行 取消"),
            EmojiEntry("⚠️", "警告", "warning alert 注意 警告"),
            EmojiEntry("❗", "感叹号", "exclamation important 重要 注意"),
            EmojiEntry("❓", "问号", "question what 疑问 什么"),
            EmojiEntry("➕", "加号", "plus add 添加"),
            EmojiEntry("➖", "减号", "minus remove 移除"),
            EmojiEntry("🔴", "红点", "red circle 红"),
            EmojiEntry("🟠", "橙点", "orange circle 橙"),
            EmojiEntry("🟡", "黄点", "yellow circle 黄"),
            EmojiEntry("🟢", "绿点", "green circle 绿 在线"),
            EmojiEntry("🔵", "蓝点", "blue circle 蓝"),
            EmojiEntry("🟣", "紫点", "purple circle 紫"),
            EmojiEntry("⬆️", "向上箭头", "arrow up 上"),
            EmojiEntry("⬇️", "向下箭头", "arrow down 下"),
            EmojiEntry("⬅️", "向左箭头", "arrow left 左"),
            EmojiEntry("➡️", "向右箭头", "arrow right 右"),
            EmojiEntry("🔄", "刷新循环", "refresh sync 刷新 同步"),
            EmojiEntry("♾️", "无限", "infinity forever loop 永恒 无限"),
            EmojiEntry("🚩", "红旗", "flag flag立flag 标记"),
            EmojiEntry("🏁", "终点旗", "checkered flag 完成 冲线")
        ])
    ]

    static let allEntries: [EmojiEntry] = {
        var seen: Set<String> = []
        var result: [EmojiEntry] = []
        for section in sections {
            for entry in section.entries where seen.insert(entry.symbol).inserted {
                result.append(entry)
            }
        }
        return result
    }()

    static let entryBySymbol: [String: EmojiEntry] = {
        Dictionary(uniqueKeysWithValues: allEntries.map { ($0.symbol, $0) })
    }()

    static func searchLocal(query: String) -> [EmojiEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }
        let terms = trimmed.split(separator: " ").map(String.init)
        return allEntries.filter { entry in
            if entry.symbol == trimmed { return true }
            return terms.allSatisfy { term in
                entry.keywords.contains(term)
            }
        }
    }

    /// Returns true if the input string is a short emoji-only sequence (1–2 emoji graphemes)
    /// suitable for triggering quick inline sticker suggestions above the composer.
    static func isSingleEmojiQuery(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2 else { return false }
        return trimmed.allSatisfy { character in
            character.unicodeScalars.contains { scalar in
                scalar.properties.isEmojiPresentation
                    || (scalar.properties.isEmoji && scalar.value >= 0x231A)
            }
        }
    }
}
