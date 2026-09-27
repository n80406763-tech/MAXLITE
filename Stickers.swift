import Foundation

struct Sticker: Identifiable, Equatable, Codable {
    var id: Int64
    var setId: Int64?
    var url: String
    var lottieUrl: String?
    var width: Int
    var height: Int
    var updateTime: Int64?

    var imageURL: URL? { URL(string: url) }
}

/// Стикеры, которые реально встречались в переписке, — их можно отправлять
/// обратно. Каталог наборов у MAX закрыт и документирован обрывочно, поэтому
/// это основной, всегда рабочий источник.
final class StickerStore: ObservableObject {
    static let shared = StickerStore()
    private let key = "recentStickers"
    private let limit = 60

    @Published private(set) var recent: [Sticker] = []
    @Published private(set) var catalog: [Sticker] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([Sticker].self, from: data) {
            recent = list
        }
    }

    var all: [Sticker] {
        var seen = Set<Int64>()
        return (recent + catalog).filter { seen.insert($0.id).inserted }
    }

    func remember(_ s: Sticker) {
        guard !s.url.isEmpty else { return }
        if let i = recent.firstIndex(where: { $0.id == s.id }) {
            recent.remove(at: i)
        }
        recent.insert(s, at: 0)
        if recent.count > limit { recent.removeLast(recent.count - limit) }
        if let data = try? JSONEncoder().encode(recent) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func setCatalog(_ list: [Sticker]) {
        catalog = list.filter { !$0.url.isEmpty }
    }
}
