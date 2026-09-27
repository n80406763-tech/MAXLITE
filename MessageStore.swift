import Foundation

/// Локальный кэш сообщений на файловой системе.
/// Каждый чат хранится в отдельном файле:
///   Application Support/MaxLiteMessages/messages_<chatId>.json
///
/// Запись происходит на фоновой очереди, чтение синхронное —
/// безопасно вызывать при старте (до отображения UI).
final class MessageStore {
    static let shared = MessageStore()

    /// Максимум сообщений на чат в хранилище
    private let maxPerChat = 2000

    private let queue = DispatchQueue(label: "ru.netrender.maxlite.messagestore",
                                      qos: .utility)
    private let baseURL: URL

    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        baseURL = appSupport.appendingPathComponent("MaxLiteMessages", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseURL,
                                                  withIntermediateDirectories: true)
    }

    // MARK: пути

    private func fileURL(for chatId: Int64) -> URL {
        baseURL.appendingPathComponent("messages_\(chatId).json")
    }

    // MARK: чтение

    /// Загружает все сохранённые сообщения для чата (синхронно).
    func load(for chatId: Int64) -> [Message] {
        let url = fileURL(for: chatId)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Message].self, from: data)) ?? []
    }

    // MARK: запись (фоновая очередь)

    /// Сохраняет весь массив сообщений (перезаписывает файл).
    func save(_ messages: [Message], for chatId: Int64) {
        let trimmed = messages.count > maxPerChat
            ? Array(messages.suffix(maxPerChat))
            : messages
        let url = fileURL(for: chatId)
        queue.async {
            guard let data = try? JSONEncoder().encode(trimmed) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Добавляет или обновляет одно сообщение в существующем массиве (merge по id).
    /// Если превышен лимит — удаляет самые старые.
    func upsert(_ message: Message, into existing: [Message]) -> [Message] {
        var list = existing
        if let idx = list.firstIndex(where: { $0.id == message.id }) {
            list[idx] = message
        } else {
            list.append(message)
            list.sort { ($0.ts, $0.id) < ($1.ts, $1.id) }
            if list.count > maxPerChat {
                list.removeFirst(list.count - maxPerChat)
            }
        }
        return list
    }

    /// Удаляет сообщения по id из сохранённого кэша.
    func remove(ids: Set<String>, from chatId: Int64) {
        queue.async { [weak self] in
            guard let self else { return }
            var cached = self.load(for: chatId)
            cached.removeAll { ids.contains($0.id) }
            guard let data = try? JSONEncoder().encode(cached) else { return }
            try? data.write(to: self.fileURL(for: chatId), options: .atomic)
        }
    }

    /// Полностью очищает кэш всех чатов (при выходе из аккаунта).
    func clearAll() {
        queue.async { [weak self] in
            guard let self else { return }
            let files = (try? FileManager.default.contentsOfDirectory(
                at: self.baseURL, includingPropertiesForKeys: nil)) ?? []
            for f in files { try? FileManager.default.removeItem(at: f) }
        }
    }
}
