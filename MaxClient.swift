import Foundation
import UserNotifications

/// Клиент неофициального WebSocket-протокола MAX (тот же, что у web.max.ru).
/// Кадры: {"ver":11,"cmd":0|1|3,"seq":N,"opcode":N,"payload":{...}}
@MainActor
final class MaxClient: ObservableObject {

    // MARK: опкоды
    private enum Op {
        static let ping = 1, initSession = 6, login = 19, contacts = 32
        static let presence = 35
        static let history = 49, chats = 53
        static let typing = 65, send = 64, msgDelete = 66, msgEdit = 67
        static let search = 73
        static let subscribe = 75
        static let fileUpload = 87
        static let stickerData = 27, stickerGet = 28
        static let reactSet = 178, reactRemove = 179
    }

    private static let wsURL = URL(string: "wss://ws-api.oneme.ru/websocket")!
    private static let origin = "https://web.max.ru"
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    private static let ver = 11

    // MARK: состояние для интерфейса
    @Published private(set) var status = "Не подключено"
    @Published private(set) var online = false
    @Published private(set) var chats: [Chat] = []
    @Published private(set) var messages: [Int64: [Message]] = [:]
    @Published private(set) var myName = ""
    @Published private(set) var typingUsers: [Int64: Set<Int64>] = [:]
    @Published private(set) var presence: [Int64: PresenceInfo] = [:]
    @Published var auth: Auth? { didSet { if auth == nil { reset() } } }
    /// Чат, открытый прямо сейчас: по нему не шлём уведомления.
    var activeChat: Int64?
    /// Чат, который нужно открыть навигацией. Заполняют selectChat/openDialogWith
    /// из глубины стека; ChatListView наблюдает и делает push в стек.
    @Published var pendingChatId: Int64?

    // MARK: внутреннее
    private var task: URLSessionWebSocketTask?
    private var session = URLSession(configuration: .default)
    private var seq = 0
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var attachWaiters: [CheckedContinuation<Void, Never>] = []
    var users: [Int64: String] = [:]
    private var rawChats: [Int64: [String: Any]] = [:]
    private var subscribed = Set<Int64>()
    private var loopTask: Task<Void, Never>?
    private let startedAt = Int64(Date().timeIntervalSince1970 * 1000)

    struct Failure: LocalizedError {
        let text: String
        var errorDescription: String? { text }
        // isAuth — сервер отверг токен. Значение не входит в конструктор,
        // чтобы никто не смог случайно создать «авторизационную» ошибку через
        // memberwise init при другом порядке аргументов.
        let isAuth: Bool

        init(text: String, isAuth: Bool = false) {
            self.text = text
            self.isAuth = isAuth
        }
    }

    init() {
        auth = Keychain.load()
    }

    // MARK: жизненный цикл

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { await self.runForever() }
    }

    func signOut() {
        Keychain.clear()
        auth = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        MessageStore.shared.clearAll()
    }

    func reloadAllChats() async {
        MessageStore.shared.clearAll()
        messages = [:]
        for chat in chats {
            await openChat(chat.id)
        }
    }

    private func reset() {
        chats = []; messages = [:]; rawChats = [:]; users = [:]
        subscribed = []; myName = ""; online = false
        typingUsers = [:]; presence = [:]
        resolveAttachWaiters()
    }

    private func runForever() async {
        var backoff: UInt64 = 2
        while !Task.isCancelled {
            guard let auth else {
                status = "Нужен вход"
                online = false
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            do {
                status = "Подключение…"
                try openSocket()
                try await handshake(auth)
                online = true
                status = "Онлайн"
                backoff = 2
                subscribed = []
                startHeartbeat()
                Task { await self.loadStickerCatalog() }
                try await readLoop()
            } catch let f as Failure where f.isAuth {
                online = false
                status = f.text
                failAllPending(f)
                Keychain.clear()
                self.auth = nil
                continue
            } catch {
                online = false
                status = "Нет связи"
                failAllPending(error)
            }
            task?.cancel(with: .goingAway, reason: nil)
            task = nil
            resolveAttachWaiters()
            try? await Task.sleep(for: .seconds(Double(backoff)))
            backoff = min(backoff * 2, 30)
        }
    }

    private func openSocket() throws {
        var req = URLRequest(url: Self.wsURL)
        req.setValue(Self.origin, forHTTPHeaderField: "Origin")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 30
        let t = session.webSocketTask(with: req)
        t.resume()
        task = t
    }

    private func startHeartbeat() {
        Task { [weak self] in
            while let self, self.online {
                try? await Task.sleep(for: .seconds(25))
                guard self.online else { return }
                try? self.fireAndForget(Op.ping, ["interactive": true])
            }
        }
    }

    // MARK: кадры

    private func nextSeq() -> Int { seq += 1; return seq }

    private func write(_ frame: [String: Any]) throws {
        guard let task else { throw Failure(text: "нет соединения") }
        let data = try JSONSerialization.data(withJSONObject: frame)
        let text = String(decoding: data, as: UTF8.self)
        // Раньше здесь стояло `task.send(...) { _ in }` — ошибка отправки
        // проглатывалась, и запрос вис в pending до разрыва соединения.
        let box = SendResult()
        let done = DispatchSemaphore(value: 0)
        task.send(.string(text)) { err in
            box.error = err
            done.signal()
        }
        // Колбэк может сработать на любой очереди; ждём его здесь, чтобы
        // вызывающий получил результат (или брошенную ошибку) синхронно.
        done.wait()
        if box.error != nil {
            // Сообщение могло уйти частично: считаем соединение нездоровым,
            // будим все ожидающие запросы, чтобы UI не висел на спиннере.
            failAllPending(Failure(text: "Не удалось отправить запрос"))
        }
    }

    /// Мостик для колбэка send() из другого потока.
    private final class SendResult: @unchecked Sendable {
        var error: Error?
    }

    func fireAndForget(_ opcode: Int, _ payload: [String: Any]) throws {
        try write(["ver": Self.ver, "cmd": 0, "seq": nextSeq(),
                   "opcode": opcode, "payload": payload])
    }

    private func readFrame() async throws -> [String: Any] {
        guard let task else { throw Failure(text: "нет соединения") }
        let msg = try await task.receive()
        let data: Data
        switch msg {
        case .string(let s): data = Data(s.utf8)
        case .data(let d): data = d
        @unknown default: throw Failure(text: "неизвестный тип кадра")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(text: "не разобрал кадр")
        }
        return obj
    }

    /// Запрос с ожиданием ответа по seq.
    @discardableResult
    func request(_ opcode: Int, _ payload: [String: Any]) async throws -> [String: Any] {
        let s = nextSeq()
        let frame: [String: Any] = ["ver": Self.ver, "cmd": 0, "seq": s,
                                    "opcode": opcode, "payload": payload]
        return try await withCheckedThrowingContinuation { cont in
            pending[s] = cont
            do {
                try write(frame)
            } catch {
                pending.removeValue(forKey: s)
                cont.resume(throwing: error)
            }
        }
    }

    private func failAllPending(_ error: Error) {
        let all = pending
        pending = [:]
        for (_, c) in all { c.resume(throwing: error) }
    }

    // MARK: вход

    private func handshake(_ auth: Auth) async throws {
        try fireAndForget(Op.initSession, [
            "userAgent": [
                "deviceType": "WEB", "pushDeviceType": "WEBPUSH",
                "locale": "ru", "deviceLocale": "ru",
                "osVersion": "macOS", "deviceName": "Chrome",
                "headerUserAgent": Self.userAgent,
                "appVersion": "26.6.17", "screen": "1470x956 2.0x",
                "timezone": TimeZone.current.identifier,
            ],
            "deviceId": auth.deviceId,
        ])
        while true {
            let f = try await readFrame()
            if f.int("opcode") == Op.initSession, let cmd = f.int("cmd"), cmd == 1 || cmd == 3 {
                if cmd == 3 { throw Failure(text: "INIT отклонён") }
                break
            }
        }

        try fireAndForget(Op.login, [
            "interactive": true, "token": auth.token,
            "chatsCount": 100, "chatsSync": 100,
            "contactsSync": 0, "presenceSync": 0, "draftsSync": 0,
        ])
        while true {
            let f = try await readFrame()
            guard f.int("opcode") == Op.login, let cmd = f.int("cmd"), cmd == 1 || cmd == 3 else {
                continue
            }
            let p = f.dict("payload") ?? [:]
            if cmd == 3 {
                let msg = p.str("localizedMessage") ?? p.str("message") ?? "токен не принят"
                throw Failure(text: msg, isAuth: true)
            }
            absorbLogin(p, auth: auth)
            return
        }
    }

    private func absorbLogin(_ p: [String: Any], auth: Auth) {
        if let contact = p.dict("profile")?.dict("contact") {
            absorbUsers([contact])
            myName = users[auth.viewerId] ?? ""
        }
        // LOGIN может вернуть обновлённый токен — сохраняем, чтобы сессия
        // жила и после закрытия вкладки web.max.ru.
        if let fresh = p.str("token"), fresh != auth.token {
            var updated = auth
            updated.token = fresh
            Keychain.save(updated)
            self.auth = updated
        }
        absorbUsers(p.arr("users") ?? [])
        for c in p.arr("chats") ?? [] { absorbChat(c) }
        rebuildChats()
        Task { await resolveMissingNames() }
    }

    // MARK: приём

    private func readLoop() async throws {
        while true {
            let f = try await readFrame()
            let cmd = f.int("cmd") ?? 0
            let op = f.int("opcode") ?? 0
            let payload = f.dict("payload") ?? [:]

            if cmd == 0 {
                if op == Op.ping {
                    try? fireAndForget(Op.ping, ["interactive": true])
                } else {
                    handlePush(op, payload)
                }
                continue
            }
            guard let s = f.int("seq"), let cont = pending.removeValue(forKey: s) else { continue }
            if cmd == 3 {
                let msg = payload.str("localizedMessage") ?? payload.str("message")
                    ?? payload.str("error") ?? "ошибка"
                cont.resume(throwing: Failure(text: msg))
            } else {
                cont.resume(returning: payload)
            }
        }
    }

    /// Опкоды пушей ниже подтверждены реверс-инжинирингом трафика MAX.
    /// Опкод «новое/удалённое сообщение» официально не задокументирован —
    /// для него смотрим на форму payload (запасной путь в конце функции).
    ///
    /// Важно: opcode 132 (NOTIF_PRESENCE) — только push. Отправка его как
    /// запроса рвёт соединение, поэтому здесь он только читается.
    private func handlePush(_ op: Int, _ p: [String: Any]) {
        switch op {
        case 129: // NOTIF_TYPING
            if let cid = p.i64("chatId"), let uid = p.i64("userId") {
                markTyping(userId: uid, in: cid)
            }
            return
        case 132: // NOTIF_PRESENCE — push-only, никогда не отправлять как запрос
            if let uid = p.i64("userId"), let pr = p.dict("presence") {
                presence[uid] = PresenceInfo(seen: pr.i64("seen") ?? 0, online: pr.int("status") == 1)
            }
            return
        case 136: // NOTIF_ATTACH — файл готов к прикреплению
            resolveAttachWaiters()
            return
        case 156: // NOTIF_REACTION
            if let cid = p.i64("chatId") {
                let mid = p.str("messageId") ?? p.i64("messageId").map(String.init)
                if let mid { applyReactionInfo(p.dict("reactionInfo") ?? [:], messageId: mid, chatId: cid) }
            }
            return
        default:
            break
        }

        if let m = p.dict("message"), let cid = p.i64("chatId") {
            store(message: m, chatId: cid)
            return
        }
        if let cid = p.i64("chatId"), let ids = p["messageIds"] as? [Any] {
            removeLocal(ids: ids, chatId: cid)
            return
        }
        if let c = p.dict("chat") {
            absorbChat(c)
            rebuildChats()
        }
    }

    // MARK: данные

    private func absorbUsers(_ list: [[String: Any]]) {
        for u in list {
            guard let id = u.i64("id") else { continue }
            let names = u.arr("names") ?? []
            let full = names.first(where: { $0.str("type") == "FULL_NAME" }) ?? names.first
            if let n = full?.str("name"), !n.isEmpty { users[id] = n }
        }
    }

    private func absorbChat(_ c: [String: Any]) {
        guard let id = c.i64("id"), let type = c.str("type") else { return }
        guard ["CHAT", "CHANNEL", "DIALOG"].contains(type) else { return }
        if let st = c.str("status"), st != "ACTIVE" { return }
        rawChats[id] = rawChats[id].map { old in old.merging(c) { _, new in new } } ?? c
    }

    private func dialogPartner(_ c: [String: Any]) -> Int64? {
        guard let parts = c.dict("participants") else { return nil }
        let me = auth?.viewerId
        for key in parts.keys {
            if let uid = Int64(key), uid != me { return uid }
        }
        return nil
    }

    private func rebuildChats() {
        chats = rawChats.values.compactMap { c -> Chat? in
            guard let id = c.i64("id"), let type = c.str("type") else { return nil }
            let kind: Chat.Kind = type == "CHANNEL" ? .channel : (type == "DIALOG" ? .dialog : .chat)
            var title = c.str("title") ?? ""
            if kind == .dialog, title.isEmpty {
                if let uid = dialogPartner(c) { title = users[uid] ?? "Диалог \(uid)" }
                else { title = "Диалог" }
            }
            if title.isEmpty { title = "Чат \(id)" }
            let iconStr = c.dict("picture")?.str("url") ?? c.str("baseIconUrl")
            return Chat(
                id: id,
                title: title,
                kind: kind,
                members: kind == .dialog ? nil : c.int("participantsCount"),
                iconURL: iconStr.flatMap(URL.init(string:)),
                lastTime: c.dict("lastMessage")?.i64("time") ?? 0
            )
        }
        .sorted { $0.lastTime > $1.lastTime }
    }

    /// Собственный ID собеседника для диалога — используется, чтобы
    /// показать presence (в сети / был недавно) в шапке чата.
    func dialogPartnerId(_ chatId: Int64) -> Int64? {
        guard let c = rawChats[chatId] else { return nil }
        return dialogPartner(c)
    }

    // MARK: сборка и хранение сообщений

    private func buildMessage(_ m: [String: Any], chatId: Int64) -> Message? {
        guard let rawId = m["id"] else { return nil }
        let mid = (rawId as? String) ?? String(describing: (rawId as? NSNumber)?.int64Value ?? 0)
        let sender = m.i64("sender")
        var atts = (m["attaches"] as? [[String: Any]] ?? []).enumerated().map {
            parseAttachment($0.element, index: $0.offset, mid: mid)
        }
        for a in atts { if let st = a.asSticker { StickerStore.shared.remember(st) } }

        var body = m.str("text") ?? ""
        var quote: QuotedText?
        var forwardedFrom: String?

        // Обработка link.type == "REPLY" (цитата)
        var replyMessageId: String?
        var replyUserId: Int64?
        if let link = m.dict("link"), link.str("type") == "REPLY",
           let replyMsg = link.dict("message") {
            var replyText = replyMsg.str("text") ?? ""

            // Если текст пустой, но есть вложения — показываем label первого
            if replyText.isEmpty, let replyAtts = replyMsg["attaches"] as? [[String: Any]], !replyAtts.isEmpty {
                let firstAtt = parseAttachment(replyAtts[0], index: 0, mid: "")
                replyText = firstAtt.label
            }

            let replySender = replyMsg.i64("sender")
            let replyAuthor = replySender.flatMap { users[$0] } ?? "Пользователь"
            replyMessageId = replyMsg.str("id") ?? replyMsg.i64("id").map(String.init)
            replyUserId = replySender
            quote = QuotedText(author: replyAuthor, text: replyText, messageId: replyMessageId, userId: replyUserId)
        } else {
            // Старый формат: парсим из текста
            (quote, body) = Self.parseQuote(body)
        }

        // Обработка link.type == "FORWARD" (пересланное)
        var forwardedInfo: ForwardedInfo?
        if let link = m.dict("link"), link.str("type") == "FORWARD" {
            var fwdAuthor: String?
            var fwdUserId: Int64?
            var fwdChatId: Int64?

            // Проверяем, есть ли chatId (пересылка из канала/группы)
            if let chatId = link.i64("chatId") {
                fwdChatId = chatId
                // Пытаемся получить название канала/группы
                if let chat = rawChats[chatId] {
                    fwdAuthor = chat.str("title") ?? "Чат"
                } else {
                    fwdAuthor = "Чат"
                }
            }

            // Если есть вложенное сообщение
            if let fwdMsg = link.dict("message") {
                let fwdText = fwdMsg.str("text") ?? ""
                let senderId = fwdMsg.i64("sender")

                // Только если это НЕ канал (т.е. личная пересылка)
                if fwdChatId == nil {
                    fwdUserId = senderId
                    fwdAuthor = senderId.flatMap { users[$0] } ?? "Пользователь"
                }

                // Добавляем вложения из пересланного
                let fwdAtts = (fwdMsg["attaches"] as? [[String: Any]] ?? []).enumerated().map {
                    parseAttachment($0.element, index: atts.count + $0.offset, mid: mid)
                }
                atts.append(contentsOf: fwdAtts)

                // Если текст пустой, заменяем пересланным
                if body.isEmpty {
                    body = fwdText
                }
            } else {
                // Старый формат
                fwdUserId = link.i64("senderId")
                if let fwdName = link.str("senderName") {
                    fwdAuthor = fwdName
                } else if let uid = fwdUserId {
                    fwdAuthor = users[uid] ?? "Пользователь \(uid)"
                }
            }

            // Если есть chatName — пересылка из канала/группы
            if let chatName = link.str("chatName") {
                fwdAuthor = chatName
                fwdChatId = link.i64("chatId")
            }

            if let author = fwdAuthor {
                forwardedInfo = ForwardedInfo(author: author, userId: fwdUserId, chatId: fwdChatId)
            }
        }

        let reactionInfo = m.dict("reactionInfo") ?? [:]
        let counters = (reactionInfo.arr("counters") ?? []).compactMap { c -> ReactionCount? in
            guard let e = c.str("reaction"), let n = c.int("count") else { return nil }
            return ReactionCount(emoji: e, count: n)
        }

        // Raw JSON для debug режима
        let rawJSON = AppSettings.shared.debugMode
            ? (try? JSONSerialization.data(withJSONObject: m, options: [.prettyPrinted, .sortedKeys]))
                .flatMap { String(data: $0, encoding: .utf8) }
            : nil

        return Message(
            id: mid,
            chatId: chatId,
            ts: m.i64("time") ?? 0,
            text: body,
            senderId: sender,
            senderName: sender.flatMap { users[$0] } ?? "",
            attachments: atts,
            edited: m.str("status") == "EDITED",
            reactions: counters,
            yourReaction: reactionInfo.str("yourReaction"),
            quote: quote,
            forwardedFrom: forwardedInfo,
            rawJSON: rawJSON
        )
    }

    /// Приложение шлёт "ответ" как обычный текст с цитатой первой строкой
    /// (см. `send(_:to:quoting:)`) — у протокола MAX нет подтверждённого
    /// поля для серверного reply, только `link.type == "forward"`,
    /// причём не для исходящих. Здесь разбираем такую цитату обратно,
    /// чтобы показать её как обычный "ответ на сообщение" в интерфейсе.
    private static func parseQuote(_ text: String) -> (QuotedText?, String) {
        guard text.hasPrefix("› "), let nl = text.firstIndex(of: "\n") else { return (nil, text) }
        let firstLine = String(text[text.index(text.startIndex, offsetBy: 2)..<nl])
        guard let sep = firstLine.range(of: ": ") else { return (nil, text) }
        let author = String(firstLine[firstLine.startIndex..<sep.lowerBound])
        let quoted = String(firstLine[sep.upperBound...])
        let body = String(text[text.index(after: nl)...])
        return (QuotedText(author: author, text: quoted), body)
    }

    private func store(message m: [String: Any], chatId: Int64) {
        guard let msg = buildMessage(m, chatId: chatId) else { return }
        let isNew = messages[chatId]?.contains(where: { $0.id == msg.id }) != true
        var list = MessageStore.shared.upsert(msg, into: messages[chatId] ?? [])
        messages[chatId] = list
        if isNew { notifyIfNeeded(msg, chatId: chatId) }
        // Сохраняем весь обновлённый список на диск
        MessageStore.shared.save(list, for: chatId)
        UnreadManager.shared.updateUnreadCount(for: chatId, messages: list)
    }

    private func removeLocal(ids: [Any], chatId: Int64) {
        let strIds = Set(ids.compactMap { v -> String? in
            if let n = v as? NSNumber { return n.stringValue }
            if let s = v as? String { return s }
            return nil
        })
        guard !strIds.isEmpty else { return }
        messages[chatId]?.removeAll { strIds.contains($0.id) }
        // Синхронно удаляем из дискового кэша
        MessageStore.shared.remove(ids: strIds, from: chatId)
    }

    private func applyReactionInfo(_ info: [String: Any], messageId: String, chatId: Int64) {
        guard var list = messages[chatId], let idx = list.firstIndex(where: { $0.id == messageId })
        else { return }
        let counters = (info.arr("counters") ?? []).compactMap { c -> ReactionCount? in
            guard let e = c.str("reaction"), let n = c.int("count") else { return nil }
            return ReactionCount(emoji: e, count: n)
        }
        list[idx].reactions = counters
        list[idx].yourReaction = info.str("yourReaction")
        messages[chatId] = list
    }

    /// MSG_REACT_REMOVE отвечает голым ACK без reactionInfo — обновляем
    /// счётчик локально, не дожидаясь push.
    private func clearYourReactionLocally(messageId: String, chatId: Int64) {
        guard var list = messages[chatId], let idx = list.firstIndex(where: { $0.id == messageId })
        else { return }
        if let mine = list[idx].yourReaction,
           let ridx = list[idx].reactions.firstIndex(where: { $0.emoji == mine }) {
            list[idx].reactions[ridx].count = max(0, list[idx].reactions[ridx].count - 1)
            if list[idx].reactions[ridx].count == 0 { list[idx].reactions.remove(at: ridx) }
        }
        list[idx].yourReaction = nil
        messages[chatId] = list
    }

    private func markTyping(userId: Int64, in chatId: Int64) {
        var set = typingUsers[chatId] ?? []
        set.insert(userId)
        typingUsers[chatId] = set
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.clearTyping(userId: userId, in: chatId)
        }
    }

    private func clearTyping(userId: Int64, in chatId: Int64) {
        typingUsers[chatId]?.remove(userId)
    }

    private func parseAttachment(_ a: [String: Any], index: Int, mid: String) -> Attachment {
        let raw = (a.str("_type") ?? a.str("type") ?? "OTHER").uppercased()
        let kind: Attachment.Kind
        switch raw {
        case "PHOTO": kind = .photo
        case "STICKER": kind = .sticker
        case "VIDEO": kind = .video
        case "FILE": kind = .file
        case "UNSUPPORTED", "AUDIO": kind = .voice
        case "CALL": kind = .call
        case "CONTROL": kind = .control
        case "SHARE": kind = .share
        default: kind = .other
        }

        // PHOTO отдаётся как baseUrl (без размера) либо готовый url.
        var link: String?
        switch kind {
        case .photo: link = a.str("baseUrl") ?? a.str("url") ?? a.str("previewUrl")
        case .sticker: link = a.str("url")
        case .file: link = a.str("fileUrl") ?? a.str("url")
        default: link = a.str("url") ?? a.str("baseUrl")
        }

        return Attachment(
            id: "\(mid).\(index)",
            kind: kind,
            url: link.flatMap(URL.init(string:)),
            width: a.int("width") ?? 0,
            height: a.int("height") ?? 0,
            name: a.str("name") ?? a.str("fileName"),
            stickerId: a.i64("stickerId"),
            setId: a.i64("setId"),
            lottieUrl: a.str("lottieUrl"),
            updateTime: a.i64("updateTime"),
            duration: a.int("duration")
        )
    }

    // MARK: уведомления

    private func notifyIfNeeded(_ msg: Message, chatId: Int64) {
        guard AppSettings.shared.notificationsOn else { return }
        guard msg.senderId != auth?.viewerId else { return }
        guard activeChat != chatId else { return }
        guard msg.ts > startedAt else { return }

        let chatTitle = chats.first(where: { $0.id == chatId })?.title ?? "MAX"
        let content = UNMutableNotificationContent()
        content.title = chatTitle
        if !msg.senderName.isEmpty, chats.first(where: { $0.id == chatId })?.kind != .dialog {
            content.subtitle = msg.senderName
        }
        content.body = msg.text.isEmpty
            ? (msg.attachments.first?.label ?? "сообщение")
            : msg.text
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: msg.id, content: content, trigger: nil))
    }

    // MARK: публичные действия — чаты и история

    func refreshChats() async {
        guard online else { return }
        do {
            let p = try await request(Op.chats, ["count": 100, "marker": 0])
            absorbUsers(p.arr("users") ?? [])
            for c in p.arr("chats") ?? [] { absorbChat(c) }
            rebuildChats()
            await resolveMissingNames()
        } catch { }
    }

    func openChat(_ chatId: Int64) async {
        // 1. Сразу показываем кэш с диска — пользователь видит историю
        //    ещё до ответа сервера.
        if messages[chatId] == nil || messages[chatId]!.isEmpty {
            let cached = MessageStore.shared.load(for: chatId)
            if !cached.isEmpty { messages[chatId] = cached }
        }

        guard online else { return }
        if !subscribed.contains(chatId) {
            _ = try? await request(Op.subscribe, ["chatId": chatId, "subscribe": true])
            subscribed.insert(chatId)
        }
        await loadHistory(chatId)
    }

    func loadHistory(_ chatId: Int64) async {
        guard online else { return }
        let last = messages[chatId]?.last?.ts
        var payload: [String: Any] = [
            "chatId": chatId, "backwardTime": 0, "forwardTime": 0,
            "getChat": false, "getMessages": true, "interactive": false,
        ]
        if let last, last > 0 {
            payload["from"] = last
            payload["backward"] = 0
            payload["forward"] = 100
        } else {
            payload["from"] = Int64(Date().timeIntervalSince1970 * 1000)
            payload["backward"] = 60
            payload["forward"] = 0
        }
        guard let p = try? await request(Op.history, payload) else { return }
        let list = p.arr("messages") ?? []
        for m in list { store(message: m, chatId: chatId) }

        let unknown = Set(list.compactMap { $0.i64("sender") }).subtracting(users.keys)
        if !unknown.isEmpty {
            await fetchContacts(Array(unknown))
            for m in list { store(message: m, chatId: chatId) }
        }
    }

    /// Загружает более старые сообщения (прокрутка вверх).
    /// Берёт timestamp самого старого известного сообщения и запрашивает
    /// backward=50 от него. Возвращает количество загруженных новых сообщений.
    @discardableResult
    func loadOlderMessages(_ chatId: Int64) async -> Int {
        guard online else { return 0 }
        guard let oldest = messages[chatId]?.first?.ts, oldest > 0 else { return 0 }

        print("📜 loadOlderMessages: загружаем старые сообщения для чата \(chatId)")
        let payload: [String: Any] = [
            "chatId": chatId,
            "backwardTime": 0, "forwardTime": 0,
            "getChat": false, "getMessages": true, "interactive": false,
            "from": oldest,
            "backward": 50,
            "forward": 0,
        ]
        guard let p = try? await request(Op.history, payload) else { return 0 }
        let list = p.arr("messages") ?? []
        print("📜 loadOlderMessages: получили \(list.count) сообщений")

        // Считаем только реально новые сообщения (которых ещё не было)
        let knownIds = Set(messages[chatId]?.map(\.id) ?? [])
        let newMsgs = list.filter { m in
            let rawId = m["id"]
            let mid = (rawId as? String) ?? String(describing: (rawId as? NSNumber)?.int64Value ?? 0)
            return !knownIds.contains(mid)
        }

        print("📜 loadOlderMessages: сохраняем сообщения (первый проход)")
        for m in list { store(message: m, chatId: chatId) }

        let unknown = Set(list.compactMap { $0.i64("sender") }).subtracting(users.keys)
        print("📜 loadOlderMessages: неизвестных отправителей: \(unknown.count) (\(Array(unknown)))")

        if !unknown.isEmpty {
            print("📜 loadOlderMessages: вызываем fetchContacts")
            await fetchContacts(Array(unknown))
            print("📜 loadOlderMessages: после fetchContacts, пересохраняем сообщения")
            for m in list { store(message: m, chatId: chatId) }
            print("📜 loadOlderMessages: готово, проверяем итоговые имена")
            if let msgs = messages[chatId] {
                for msg in msgs.prefix(5) {
                    print("📜 msg[\(msg.id)]: sender=\(msg.senderId?.description ?? "nil"), senderName='\(msg.senderName)'")
                }
            }
        }
        return newMsgs.count
    }

    /// Полнотекстовый поиск сообщений внутри одного чата (opcode 73).
    /// Глобального поиска по всем чатам протокол не даёт надёжного метода.
    func searchMessages(_ query: String, in chatId: Int64, count: Int = 30) async throws -> [Message] {
        let p = try await request(Op.search, ["query": query, "count": count, "chatId": chatId])
        let results = p.arr("result") ?? []
        return results.compactMap { r in
            r.dict("message").flatMap { buildMessage($0, chatId: chatId) }
        }
    }

    // MARK: публичные действия — отправка

    /// `quoting` — цитата предыдущего сообщения, вшивается первой строкой
    /// текста (см. комментарий у `parseQuote`). Это не серверный reply,
    /// а текстовая цитата, которая ляжет и в официальном клиенте.
    func send(_ text: String, to chatId: Int64, quoting: QuotedText? = nil) async throws {
        var finalText = text
        if let q = quoting {
            let snippet = String(q.text.prefix(160))
            finalText = "› \(q.author): \(snippet)\n\(text)"
        }
        let payload: [String: Any] = [
            "chatId": chatId,
            "message": [
                "text": finalText,
                "cid": Int64(Date().timeIntervalSince1970 * 1000),
                "elements": [], "attaches": [],
            ],
            "notify": true,
        ]
        let p = try await request(Op.send, payload)
        if let m = p.dict("message") { store(message: m, chatId: chatId) }
    }

    /// Формат взят из кода веб-клиента MAX: sendChatSticker шлёт
    /// attaches:[{_type:"STICKER", stickerId, width, height, url, lottieUrl}].
    func sendSticker(_ st: Sticker, to chatId: Int64) async throws {
        var attach: [String: Any] = [
            "_type": "STICKER",
            "stickerId": st.id,
            "width": st.width,
            "height": st.height,
            "url": st.url,
        ]
        if let l = st.lottieUrl { attach["lottieUrl"] = l }
        if let u = st.updateTime { attach["updateTime"] = u }

        let payload: [String: Any] = [
            "chatId": chatId,
            "message": [
                "text": "",
                "cid": Int64(Date().timeIntervalSince1970 * 1000),
                "elements": [],
                "attaches": [attach],
            ],
            "notify": true,
        ]
        let p = try await request(Op.send, payload)
        if let m = p.dict("message") { store(message: m, chatId: chatId) }
        StickerStore.shared.remember(st)
    }

    func editMessage(_ messageId: String, newText: String, in chatId: Int64) async throws {
        let payload: [String: Any] = [
            "chatId": chatId,
            "messageId": messageId,
            "text": newText,
            "elements": [],
            "attachments": [],
        ]
        let p = try await request(Op.msgEdit, payload)
        if let m = p.dict("message") { store(message: m, chatId: chatId) }
    }

    enum DeleteScope { case onlyMe, everyone }

    /// `forMe: false` физически удаляет сообщение у всех участников без
    /// возможности восстановления. По документации есть баг: связка
    /// CHAT_ACTIVITY(92) → MSG_DELETE(forMe:false) удаляет вообще все
    /// сообщения до отметки, а не только выбранные. Поэтому приложение
    /// НИКОГДА не вызывает opcode 92 — нигде в коде его нет и не будет.
    func deleteMessage(_ messageId: String, in chatId: Int64, scope: DeleteScope) async throws {
        let idValue: Any = Int64(messageId) ?? messageId
        let payload: [String: Any] = [
            "chatId": chatId,
            "messageIds": [idValue],
            "forMe": scope == .onlyMe,
        ]
        _ = try await request(Op.msgDelete, payload)
        messages[chatId]?.removeAll { $0.id == messageId }
    }

    func setReaction(_ emoji: String, on messageId: String, in chatId: Int64) async throws {
        let midValue: Any = Int64(messageId) ?? messageId
        let payload: [String: Any] = [
            "chatId": chatId,
            "messageId": midValue,
            "reaction": ["reactionType": "EMOJI", "id": emoji],
        ]
        let p = try await request(Op.reactSet, payload)
        if let info = p.dict("reactionInfo") {
            applyReactionInfo(info, messageId: messageId, chatId: chatId)
        }
    }

    func removeReaction(on messageId: String, in chatId: Int64) async throws {
        let midValue: Any = Int64(messageId) ?? messageId
        _ = try await request(Op.reactRemove, ["chatId": chatId, "messageId": midValue])
        clearYourReactionLocally(messageId: messageId, chatId: chatId)
    }

    func sendTyping(in chatId: Int64) {
        // Режим скрытности: не отправляем индикатор набора
        guard !AppSettings.shared.stealthMode else { return }
        try? fireAndForget(Op.typing, ["chatId": chatId])
    }

    func refreshPresence(for userIds: [Int64]) async {
        // Режим скрытности: не запрашиваем presence (не показываем, что мы онлайн)
        guard !AppSettings.shared.stealthMode else { return }
        guard online, !userIds.isEmpty else { return }
        guard let p = try? await request(Op.presence, ["contactIds": userIds]) else { return }
        guard let dict = p.dict("presence") else { return }
        for (key, val) in dict {
            guard let uid = Int64(key), let info = val as? [String: Any] else { continue }
            presence[uid] = PresenceInfo(seen: info.i64("seen") ?? 0, online: false)
        }
    }

    /// Файл: FILE_UPLOAD(87) → HTTP POST на выданный URL → дождаться
    /// NOTIF_ATTACH(136) → MSG_SEND с attaches:[{_type:"FILE", fileId, token}].
    /// Ждём максимум 8 с — если push не пришёл, отправляем всё равно:
    /// сервер в наблюдаемом трафике иногда его не дублирует.
    func sendFile(data: Data, filename: String, mimeType: String, to chatId: Int64) async throws {
        let ext = (filename as NSString).pathExtension
        let up = try await request(Op.fileUpload, [
            "name": filename, "size": data.count,
            "ext": ext.isEmpty ? "bin" : ext, "count": 1,
        ])
        guard let info = up.arr("info")?.first,
              let urlStr = info.str("url"), let uploadURL = URL(string: urlStr) else {
            throw Failure(text: "сервер не выдал ссылку для загрузки")
        }

        try await httpUploadMultipart(data: data, filename: filename, mimeType: mimeType, to: uploadURL)
        await waitForAttachReady()

        var attach: [String: Any] = ["_type": "FILE", "name": filename, "size": data.count]
        if let fileId = info.str("fileId") { attach["fileId"] = fileId }
        if let token = info.str("token") { attach["token"] = token }

        let payload: [String: Any] = [
            "chatId": chatId,
            "message": [
                "text": "", "cid": Int64(Date().timeIntervalSince1970 * 1000),
                "elements": [], "attaches": [attach],
            ],
            "notify": true,
        ]
        let p = try await request(Op.send, payload)
        if let m = p.dict("message") { store(message: m, chatId: chatId) }
    }

    /// Голосовое: та же загрузка, что и sendFile (FILE_UPLOAD → HTTP →
    /// NOTIF_ATTACH), но итоговое вложение помечено `_type:"AUDIO"` с полями
    /// `audioId`/`duration` — так его сериализует сам веб-клиент MAX
    /// (см. `attachToPlain` в его коде: `{_type:"AUDIO", audioId:e.id,
    /// duration:e.duration, wave:e.wave, token:e.token}`). Это лучшее, что
    /// удалось подтвердить: официальной документации на отправку голосовых
    /// нет, а этот путь взят из их собственного шипящего JS, не придуман.
    /// Поле `wave` (миниатюра формы волны) не шлём — это только
    /// косметика для отображения, не обязательное поле.
    func sendVoice(fileURL: URL, durationMs: Int, to chatId: Int64) async throws {
        let data = try Data(contentsOf: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let up = try await request(Op.fileUpload, [
            "name": "voice.m4a", "size": data.count, "ext": "m4a", "count": 1,
        ])
        guard let info = up.arr("info")?.first,
              let urlStr = info.str("url"), let uploadURL = URL(string: urlStr) else {
            throw Failure(text: "сервер не выдал ссылку для загрузки")
        }

        try await httpUploadMultipart(data: data, filename: "voice.m4a", mimeType: "audio/mp4", to: uploadURL)
        await waitForAttachReady()

        var attach: [String: Any] = ["_type": "AUDIO", "duration": durationMs]
        if let fileId = info.str("fileId") { attach["audioId"] = fileId }
        if let token = info.str("token") { attach["token"] = token }

        let payload: [String: Any] = [
            "chatId": chatId,
            "message": [
                "text": "", "cid": Int64(Date().timeIntervalSince1970 * 1000),
                "elements": [], "attaches": [attach],
            ],
            "notify": true,
        ]
        let p = try await request(Op.send, payload)
        if let m = p.dict("message") { store(message: m, chatId: chatId) }
    }

    private func httpUploadMultipart(data: Data, filename: String, mimeType: String, to url: URL) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let boundary = "MaxLite-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
            .data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure(text: "загрузка файла не удалась")
        }
    }

    private func waitForAttachReady(timeout: Duration = .seconds(8)) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            attachWaiters.append(cont)
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.resolveAttachWaiters()
            }
        }
    }

    private func resolveAttachWaiters() {
        let list = attachWaiters
        attachWaiters = []
        for c in list { c.resume() }
    }

    /// Попытка вытащить каталог стикеров. Документация по нему обрывочная,
    /// поэтому неудача здесь не считается ошибкой — остаются «недавние».
    func loadStickerCatalog() async {
        guard online else { return }
        guard let data = try? await request(Op.stickerData, ["type": "STICKER", "sync": 0])
        else { return }

        var ids: [Int64] = []
        if let updates = data["stickersUpdates"] as? [String: Any] {
            ids = updates.keys.compactMap(Int64.init)
        }
        if ids.isEmpty, let order = data["stickersOrder"] as? [Any] {
            ids = order.compactMap { ($0 as? NSNumber)?.int64Value }
        }
        guard !ids.isEmpty else { return }

        guard let got = try? await request(Op.stickerGet,
                                           ["type": "STICKER", "ids": Array(ids.prefix(120))])
        else { return }
        let raw = (got.arr("stickers") ?? got.arr("objects") ?? [])
        let list = raw.compactMap { o -> Sticker? in
            guard let id = o.i64("id"), let u = o.str("url") else { return nil }
            return Sticker(id: id, setId: o.i64("setId"), url: u,
                           lottieUrl: o.str("lottieUrl"),
                           width: o.int("width") ?? 170, height: o.int("height") ?? 170,
                           updateTime: o.i64("updateTime"))
        }
        StickerStore.shared.setCatalog(list)
    }

    private func fetchContacts(_ ids: [Int64]) async {
        guard !ids.isEmpty else { return }
        print("🔍 fetchContacts: запрашиваем \(ids.count) пользователей: \(ids)")
        if let p = try? await request(Op.contacts, ["contactIds": Array(ids.prefix(100))]) {
            let contacts = p.arr("contacts") ?? []
            print("🔍 fetchContacts: получили \(contacts.count) контактов")
            absorbUsers(contacts)
            print("🔍 fetchContacts: users словарь теперь содержит \(users.count) записей")
            for id in ids {
                if let name = users[id] {
                    print("🔍 fetchContacts: user[\(id)] = \(name)")
                } else {
                    print("⚠️ fetchContacts: user[\(id)] = НЕ НАЙДЕН")
                }
            }
        } else {
            print("❌ fetchContacts: запрос не вернул данных")
        }
    }

    /// У диалогов title часто пуст — имя собеседника приходится добирать.
    private func resolveMissingNames() async {
        var need: Set<Int64> = []
        for c in rawChats.values where c.str("type") == "DIALOG" && (c.str("title") ?? "").isEmpty {
            if let uid = dialogPartner(c), users[uid] == nil { need.insert(uid) }
        }
        guard !need.isEmpty else { return }
        await fetchContacts(Array(need))
        rebuildChats()
    }

    // MARK: навигация

    func selectChat(_ chatId: Int64) async {
        guard chats.contains(where: { $0.id == chatId }) else { return }
        activeChat = chatId
        if messages[chatId] == nil {
            await loadHistory(chatId)
        }
        // Навигация не в нашей власти: ChatListView выталкивает его в стек.
        pendingChatId = chatId
    }

    func openDialogWith(userId: Int64) async {
        if let existing = chats.first(where: { $0.kind == .dialog && $0.id == userId }) {
            await selectChat(existing.id)
            return
        }

        let userName = users[userId] ?? "Пользователь"
        let newChat = Chat(id: userId, title: userName, kind: .dialog, members: nil,
                          iconURL: nil, lastTime: Int64(Date().timeIntervalSince1970 * 1000))
        chats.insert(newChat, at: 0)
        activeChat = userId
        pendingChatId = userId
    }
}
