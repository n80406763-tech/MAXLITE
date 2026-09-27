import Foundation

/// Менеджер для подсчета непрочитанных сообщений
@MainActor
final class UnreadManager: ObservableObject {
    static let shared = UnreadManager()

    @Published private(set) var unreadCounts: [Int64: Int] = [:]

    private var lastReadTimestamps: [Int64: Int64] = [:]
    private let defaults = UserDefaults.standard
    private let key = "lastReadTimestamps"

    private init() {
        loadTimestamps()
    }

    func markAsRead(chatId: Int64, upToTimestamp: Int64) {
        lastReadTimestamps[chatId] = upToTimestamp
        unreadCounts[chatId] = 0
        saveTimestamps()
    }

    func updateUnreadCount(for chatId: Int64, messages: [Message]) {
        // Ловим первую встречу с чатом. Краеугольный камень: в первый раз мы не
        // знаем, где начинался непрочитанный — но считать ВСЮ загруженную историю
        // непрочитанной нельзя: она неделями старая. Поэтому инициализируем отметку
        // временем ПОСЛЕДНЕГО известного сообщения (всё показанное = прочитано) и
        // ноль непрочитанных. Дальше отметка двигается вперёд через markAsRead.
        if lastReadTimestamps[chatId] == nil, let last = messages.map(\.ts).max() ?? messages.last?.ts, last > 0 {
            lastReadTimestamps[chatId] = last
            saveTimestamps()
        }

        guard let lastRead = lastReadTimestamps[chatId] else {
            unreadCounts[chatId] = 0
            return
        }

        let unread = messages.filter { $0.ts > lastRead }.count
        unreadCounts[chatId] = unread
    }

    func totalUnread() -> Int {
        unreadCounts.values.reduce(0, +)
    }

    private func loadTimestamps() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: Int64].self, from: data) {
            lastReadTimestamps = decoded.compactMapKeys { Int64($0) }
        }
    }

    private func saveTimestamps() {
        let stringKeyed = lastReadTimestamps.reduce(into: [String: Int64]()) { result, pair in
            result[String(pair.key)] = pair.value
        }
        if let data = try? JSONEncoder().encode(stringKeyed) {
            defaults.set(data, forKey: key)
        }
    }

    func clearAll() {
        unreadCounts.removeAll()
        lastReadTimestamps.removeAll()
        saveTimestamps()
    }
}

extension Dictionary {
    func compactMapKeys<T: Hashable>(_ transform: (Key) throws -> T?) rethrows -> [T: Value] {
        try reduce(into: [:]) { result, pair in
            if let newKey = try transform(pair.key) {
                result[newKey] = pair.value
            }
        }
    }
}

/// Расширение для MaxClient - интеграция с UnreadManager
extension MaxClient {
    func updateUnreadCounts() {
        for (chatId, messages) in messages {
            UnreadManager.shared.updateUnreadCount(for: chatId, messages: messages)
        }
    }

    func markChatAsRead(_ chatId: Int64) {
        guard let lastMessage = messages[chatId]?.last else { return }
        UnreadManager.shared.markAsRead(chatId: chatId, upToTimestamp: lastMessage.ts)
    }
}
