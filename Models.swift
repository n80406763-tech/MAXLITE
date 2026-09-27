import Foundation
import CoreGraphics

struct Chat: Identifiable, Equatable {
    var id: Int64
    var title: String
    var kind: Kind
    var members: Int?
    var iconURL: URL?
    var lastTime: Int64

    enum Kind: String, Codable { case dialog, chat, channel }

    var subtitle: String {
        let base: String
        switch kind {
        case .dialog: base = "личный чат"
        case .channel: base = "канал"
        case .chat: base = "группа"
        }
        if let m = members, m > 0 { return "\(base) · \(m)" }
        return base
    }

    var initial: String {
        String(title.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }
}

struct Attachment: Identifiable, Equatable, Codable {
    enum Kind: String, Codable {
        case photo, sticker, video, file, voice, call, control, share, other
    }
    var id: String
    var kind: Kind
    var url: URL?
    var width: Int
    var height: Int
    var name: String?
    var stickerId: Int64?
    var setId: Int64?
    var lottieUrl: String?
    var updateTime: Int64?
    var duration: Int?   // мс, только для voice/video

    var aspect: CGFloat {
        guard width > 0, height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }

    var label: String {
        switch kind {
        case .photo: return "фото"
        case .sticker: return "стикер"
        case .video: return "видео"
        case .file: return name ?? "файл"
        case .voice: return "голосовое"
        case .call: return "звонок"
        case .control: return "событие"
        case .share: return "ссылка"
        case .other: return "вложение"
        }
    }

    var asSticker: Sticker? {
        guard kind == .sticker, let sid = stickerId, let u = url else { return nil }
        return Sticker(id: sid, setId: setId, url: u.absoluteString,
                       lottieUrl: lottieUrl, width: width, height: height,
                       updateTime: updateTime)
    }
}

struct PresenceInfo: Equatable {
    var seen: Int64
    var online: Bool
}

struct ReactionCount: Identifiable, Equatable, Codable {
    var emoji: String
    var count: Int
    var id: String { emoji }
}

/// Текстовая цитата над сообщением — реализация "ответа" на стороне
/// приложения. У протокола MAX подтверждённого поля для серверного reply
/// нет (документирован только `link.type = "forward"`), поэтому цитата
/// просто вшивается в текст перед отправкой, а здесь хранится для показа.
struct QuotedText: Equatable, Codable {
    var author: String
    var text: String
    var messageId: String?
    var userId: Int64?
}

struct ForwardedInfo: Equatable, Codable {
    var author: String
    var userId: Int64?
    var chatId: Int64?
}

struct Message: Identifiable, Equatable, Codable {
    var id: String
    var chatId: Int64
    var ts: Int64
    var text: String
    var senderId: Int64?
    var senderName: String
    var attachments: [Attachment]
    var edited: Bool
    var reactions: [ReactionCount] = []
    var yourReaction: String?
    var quote: QuotedText?
    var forwardedFrom: ForwardedInfo?
    var rawJSON: String?

    var date: Date { Date(timeIntervalSince1970: Double(ts) / 1000) }
    var isCallEvent: Bool { attachments.contains { $0.kind == .call } }
}

// Мелкие помощники для разбора динамического JSON протокола MAX.
extension Dictionary where Key == String, Value == Any {
    func dict(_ k: String) -> [String: Any]? { self[k] as? [String: Any] }
    func arr(_ k: String) -> [[String: Any]]? { self[k] as? [[String: Any]] }
    func str(_ k: String) -> String? { self[k] as? String }
    func i64(_ k: String) -> Int64? {
        if let n = self[k] as? NSNumber { return n.int64Value }
        if let s = self[k] as? String { return Int64(s) }
        return nil
    }
    func int(_ k: String) -> Int? {
        if let n = self[k] as? NSNumber { return n.intValue }
        return nil
    }
}
