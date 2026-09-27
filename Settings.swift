import Foundation
import Combine

/// Настройки приложения. Хранятся в UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var showDialogs: Bool { didSet { d.set(showDialogs, forKey: "showDialogs") } }
    @Published var showGroups: Bool { didSet { d.set(showGroups, forKey: "showGroups") } }
    @Published var showChannels: Bool { didSet { d.set(showChannels, forKey: "showChannels") } }
    @Published var hideCallEvents: Bool { didSet { d.set(hideCallEvents, forKey: "hideCallEvents") } }
    @Published var notificationsOn: Bool { didSet { d.set(notificationsOn, forKey: "notificationsOn") } }
    @Published var ipCheckOn: Bool { didSet { d.set(ipCheckOn, forKey: "ipCheckOn") } }
    @Published var showImages: Bool { didSet { d.set(showImages, forKey: "showImages") } }
    @Published var stealthMode: Bool { didSet { d.set(stealthMode, forKey: "stealthMode") } }
    @Published var autoDownloadMedia: Bool { didSet { d.set(autoDownloadMedia, forKey: "autoDownloadMedia") } }
    @Published var sendPhotosAsPhotos: Bool { didSet { d.set(sendPhotosAsPhotos, forKey: "sendPhotosAsPhotos") } }
    @Published var debugMode: Bool { didSet { d.set(debugMode, forKey: "debugMode") } }

    private static func flag(_ key: String, _ fallback: Bool) -> Bool {
        let d = UserDefaults.standard
        return d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
    }

    private init() {
        let flag = AppSettings.flag
        showDialogs = flag("showDialogs", true)
        showGroups = flag("showGroups", true)
        showChannels = flag("showChannels", true)
        hideCallEvents = flag("hideCallEvents", false)
        notificationsOn = flag("notificationsOn", true)
        ipCheckOn = flag("ipCheckOn", true)
        showImages = flag("showImages", true)
        stealthMode = flag("stealthMode", false)
        autoDownloadMedia = flag("autoDownloadMedia", true)
        sendPhotosAsPhotos = flag("sendPhotosAsPhotos", true)
        debugMode = flag("debugMode", false)
    }

    func allows(_ kind: Chat.Kind) -> Bool {
        switch kind {
        case .dialog: return showDialogs
        case .chat: return showGroups
        case .channel: return showChannels
        }
    }
}

/// Проверка, из какой страны виден ваш адрес.
///
/// Приложение не может спрятать IP — это делается только VPN/прокси на уровне
/// системы. Здесь мы лишь показываем, что видит сервер, и даём вам решить.
@MainActor
final class IPCheck: ObservableObject {
    struct Result: Equatable {
        var ip: String
        var country: String       // человекочитаемо
        var code: String          // ISO, например RU
        var isRussian: Bool { code.uppercased() == "RU" }
    }

    @Published private(set) var result: Result?
    @Published private(set) var checking = false
    @Published private(set) var error: String?

    func refresh() async {
        checking = true
        error = nil
        defer { checking = false }

        if let r = await viaIpWhoIs() { result = r; return }
        if let r = await viaCountryIs() { result = r; return }
        error = "Не удалось определить адрес"
    }

    private func fetch(_ urlString: String) async -> [String: Any]? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func viaIpWhoIs() async -> Result? {
        guard let j = await fetch("https://ipwho.is/"),
              (j["success"] as? Bool) == true,
              let ip = j["ip"] as? String,
              let code = j["country_code"] as? String else { return nil }
        let name = (j["country"] as? String) ?? code
        let city = j["city"] as? String
        return Result(ip: ip, country: city.map { "\($0), \(name)" } ?? name, code: code)
    }

    private func viaCountryIs() async -> Result? {
        guard let j = await fetch("https://api.country.is/"),
              let ip = j["ip"] as? String,
              let code = j["country"] as? String else { return nil }
        return Result(ip: ip, country: code, code: code)
    }
}
