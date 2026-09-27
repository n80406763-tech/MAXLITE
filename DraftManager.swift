import Foundation

/// Менеджер для черновиков сообщений - сохраняет текст при переключении между чатами
final class DraftManager: ObservableObject {
    static let shared = DraftManager()

    private var drafts: [Int64: String] = [:]

    private init() {}

    func save(draft: String, for chatId: Int64) {
        if draft.isEmpty {
            drafts.removeValue(forKey: chatId)
        } else {
            drafts[chatId] = draft
        }
    }

    func load(for chatId: Int64) -> String {
        drafts[chatId] ?? ""
    }

    func clear(for chatId: Int64) {
        drafts.removeValue(forKey: chatId)
    }

    func clearAll() {
        drafts.removeAll()
    }
}
