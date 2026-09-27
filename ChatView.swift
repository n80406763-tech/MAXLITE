import SwiftUI

private let quickReactions = ["👍", "❤️", "😂", "😮", "😢", "🔥", "спасибо"]

struct ChatView: View {
    let chat: Chat
    @EnvironmentObject var client: MaxClient
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var draftManager = DraftManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @State private var draft = ""
    @State private var sending = false
    @State private var sendError: String?
    @State private var showStickers = false
    @State private var showSearch = false
    @State private var lastTypingSent: Date = .distantPast
    @State private var loadingOlder = false
    @State private var hasMoreHistory = true

    @State private var replyTo: Message?
    @State private var editing: Message?
    @State private var forwarding: Message?
    @State private var deleteTarget: Message?
    @State private var confirmDeleteEveryone = false
    private var deleteDialog: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    @StateObject private var recorder = VoiceRecorder()
    @State private var voiceError: String?
    @State private var showScrollToBottom = false
    @State private var presenceTick = Date()
    @State private var highlightedMessageId: String?

    private var messages: [Message] {
        let all = client.messages[chat.id] ?? []
        return settings.hideCallEvents ? all.filter { !$0.isCallEvent } : all
    }

    private var typingSubtitle: String? {
        let ids = client.typingUsers[chat.id] ?? []
        return ids.isEmpty ? nil : "печатает…"
    }

    private var presenceSubtitle: String? {
        guard chat.kind == .dialog, let pid = client.dialogPartnerId(chat.id),
              let p = client.presence[pid] else { return nil }
        if p.online { return "в сети" }
        // Считаем от presenceTick, а не от Date() — иначе строка «замирает»
        // на моменте последней перерисовки представления.
        let mins = max(0, Int(presenceTick.timeIntervalSince1970 - Double(p.seen) / 1000) / 60)
        if mins < 1 { return "был(а) только что" }
        if mins < 60 { return "был(а) \(mins) мин назад" }
        return "был(а) недавно"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        // Кнопка/индикатор загрузки более старых сообщений
                        if hasMoreHistory {
                            Group {
                                if loadingOlder {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                } else {
                                    Button {
                                        Task { await loadOlder() }
                                    } label: {
                                        Text("Загрузить ещё...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                    }
                                }
                            }
                            .id("load_more_anchor")
                        }

                        ForEach(messages) { m in
                            bubbleView(for: m, proxy: proxy).id(m.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .onChange(of: messages.last?.id) { _, newLastId in
                    guard !loadingOlder, let lastId = newLastId else { return }
                    withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    showScrollToBottom = false
                }
                .onAppear {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if showScrollToBottom {
                        Button {
                            if let last = messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                                showScrollToBottom = false
                            }
                        } label: {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.white, .blue)
                                .shadow(radius: 4)
                        }
                        .padding()
                    }
                }
            }

            if let sendError {
                Text(sendError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }

            if let replyTo {
                composeBanner(
                    icon: "arrowshape.turn.up.left",
                    title: "Ответ · \(replyTo.senderName.isEmpty ? "Вы" : replyTo.senderName)",
                    subtitle: replyTo.text.isEmpty ? (replyTo.attachments.first?.label ?? "") : replyTo.text
                ) { self.replyTo = nil }
            }
            if editing != nil {
                composeBanner(icon: "pencil", title: "Редактирование", subtitle: nil) {
                    editing = nil; draft = ""
                }
            }

            if recorder.isRecording {
                recordingBar
            } else {
                HStack(spacing: 8) {
                    AttachPicker { data, name, mime in
                        Task { await sendFile(data: data, name: name, mime: mime) }
                    }

                    TextField("Сообщение", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                        .onChange(of: draft) { _, _ in sendTypingThrottled() }

                    Button {
                        showStickers = true
                    } label: {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 24))
                    }

                    Button {
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if text.isEmpty && editing == nil {
                            Task { await startRecording() }
                        } else {
                            Task { await primarySend() }
                        }
                    } label: {
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        Image(systemName: editing != nil ? "checkmark.circle.fill"
                              : (text.isEmpty ? "mic.circle.fill" : "arrow.up.circle.fill"))
                            .font(.system(size: 30))
                    }
                    .disabled(sending || (editing != nil && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(chat.title).font(.headline).lineLimit(1)
                    if let sub = typingSubtitle ?? presenceSubtitle {
                        Text(sub).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ChatActionsMenu(chat: chat)
                    .environmentObject(client)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ThemeToggleButton()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showStickers) {
            StickerPicker { st in
                Task {
                    do { try await client.sendSticker(st, to: chat.id) }
                    catch { sendError = "Стикер не ушёл: \(error.localizedDescription)" }
                }
            }
        }
        .sheet(item: $forwarding) { m in
            ForwardPicker(text: m.text, attachments: m.attachments,
                         fromAuthor: m.senderName.isEmpty ? "меня" : m.senderName)
                .environmentObject(client)
        }
        .sheet(isPresented: $showSearch) {
            SearchSheet(chatId: chat.id).environmentObject(client)
        }
        .confirmationDialog("Удалить сообщение?", isPresented: deleteDialog, titleVisibility: .visible) {
            Button("Удалить у себя", role: .destructive) { Task { await delete(scope: .onlyMe) } }
            Button("Удалить у всех", role: .destructive) { confirmDeleteEveryone = true }
            Button("Отмена", role: .cancel) { deleteTarget = nil }
        }
        .alert("Удалить у всех участников?", isPresented: $confirmDeleteEveryone) {
            Button("Удалить безвозвратно", role: .destructive) { Task { await delete(scope: .everyone) } }
            Button("Отмена", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Сообщение исчезнет у всех в чате. Отменить это нельзя.")
        }
        .alert("Голосовое не отправилось", isPresented: Binding(
            get: { voiceError != nil }, set: { if !$0 { voiceError = nil } }
        )) {
            Button("ОК") { voiceError = nil }
        } message: {
            Text(voiceError ?? "")
        }
        .onAppear {
            client.activeChat = chat.id
            draft = draftManager.load(for: chat.id)
            client.markChatAsRead(chat.id)
            if chat.kind == .dialog, let pid = client.dialogPartnerId(chat.id) {
                Task { await client.refreshPresence(for: [pid]) }
            }
        }
        .onDisappear {
            if client.activeChat == chat.id { client.activeChat = nil }
            draftManager.save(draft: draft, for: chat.id)
        }
        .task {
            await client.openChat(chat.id)
            // Тихое обновление истории: медленный опрос, а не бойкий цикл 3 c.
            // Push-сообщения и так приходят через handlePush; здесь лишь догоняем
            // то, что могло прийти, пока экран был закрыт, — раз в 30 секунд.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await client.loadHistory(chat.id)
            }
        }
        // Строка «был(а) N мин назад» живёт на основе presenceTick: обновляем
        // её каждую минуту, пока чат открыт. Меньше не нужно — подпись бьёт только
        // в минутной точности.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                presenceTick = Date()
            }
        }
    }

    /// Вынесено из `ForEach` отдельным методом с явными типами — иначе
    /// SwiftUI-тайпчекер не укладывается в разумное время на этом выражении.
    @ViewBuilder
    private func bubbleView(for m: Message, proxy: ScrollViewProxy) -> some View {
        let isMine = m.senderId == client.auth?.viewerId
        let canEdit = isMine && m.attachments.isEmpty
        let onEdit: (() -> Void)? = canEdit ? { editing = m; draft = m.text } : nil
        let onDelete: (() -> Void)? = isMine ? { deleteTarget = m } : nil
        let onReact: (String) -> Void = { emoji in
            Task { await toggleReaction(emoji, on: m) }
        }
        let onTapQuote: (() -> Void)? = m.quote?.messageId != nil ? {
            scrollToMessage(m.quote!.messageId!, proxy: proxy)
        } : nil
        let onTapForward: (() -> Void)? = m.forwardedFrom != nil ? {
            openForwardedChat(m.forwardedFrom!)
        } : nil

        Bubble(
            message: m,
            isMine: isMine,
            highlighted: highlightedMessageId == m.id,
            onReply: { replyTo = m },
            onForward: { forwarding = m },
            onEdit: onEdit,
            onDelete: onDelete,
            onReact: onReact,
            onTapQuote: onTapQuote,
            onTapForward: onTapForward
        )
    }

    private func scrollToMessage(_ messageId: String, proxy: ScrollViewProxy) {
        withAnimation {
            proxy.scrollTo(messageId, anchor: .center)
        }
        highlightedMessageId = messageId
        Task {
            try? await Task.sleep(for: .seconds(2))
            highlightedMessageId = nil
        }
    }

    private func openForwardedChat(_ info: ForwardedInfo) {
        if let chatId = info.chatId {
            Task {
                await client.selectChat(chatId)
            }
        } else if let userId = info.userId {
            Task {
                await client.openDialogWith(userId: userId)
            }
        }
    }

    private func toggleReaction(_ emoji: String, on m: Message) async {
        if m.yourReaction == emoji {
            try? await client.removeReaction(on: m.id, in: chat.id)
        } else {
            try? await client.setReaction(emoji, on: m.id, in: chat.id)
        }
    }

    @ViewBuilder
    private func composeBanner(icon: String, title: String, subtitle: String?, onCancel: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Button { onCancel() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    /// Формат вложения "AUDIO" взят из кода веб-клиента MAX, не из
    /// официальной документации — см. комментарий у `sendVoice` в
    /// MaxClient.swift. Если сервер его отклонит, текст ошибки будет
    /// показан ниже переписки как обычно.
    private var recordingBar: some View {
        HStack(spacing: 12) {
            Button {
                recorder.cancel()
            } label: {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(formatted(recorder.elapsed))
                    .font(.subheadline.monospacedDigit())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)

            Button {
                Task { await stopAndSendRecording() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func formatted(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func startRecording() async {
        do {
            try await recorder.start()
        } catch {
            voiceError = error.localizedDescription
        }
    }

    private func stopAndSendRecording() async {
        guard let (url, duration) = recorder.stop() else { return }
        do {
            try await client.sendVoice(fileURL: url, durationMs: Int(duration * 1000), to: chat.id)
        } catch {
            voiceError = error.localizedDescription
        }
    }

    private func sendTypingThrottled() {
        guard Date().timeIntervalSince(lastTypingSent) > 3 else { return }
        lastTypingSent = Date()
        client.sendTyping(in: chat.id)
    }

    private func primarySend() async {
        if let editing {
            await saveEdit(editing)
        } else {
            await send()
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        sendError = nil
        draft = ""
        draftManager.clear(for: chat.id)
        let quote = replyTo.map { QuotedText(author: $0.senderName.isEmpty ? "Вы" : $0.senderName, text: $0.text) }
        replyTo = nil
        do {
            try await client.send(text, to: chat.id, quoting: quote)
        } catch {
            draft = text
            sendError = "Не отправилось: \(error.localizedDescription)"
        }
        sending = false
    }

    private func saveEdit(_ original: Message) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        sendError = nil
        do {
            try await client.editMessage(original.id, newText: text, in: chat.id)
            editing = nil
            draft = ""
            draftManager.clear(for: chat.id)
        } catch {
            sendError = "Не сохранилось: \(error.localizedDescription)"
        }
        sending = false
    }

    private func delete(scope: MaxClient.DeleteScope) async {
        guard let target = deleteTarget else { return }
        deleteTarget = nil
        do {
            try await client.deleteMessage(target.id, in: chat.id, scope: scope)
        } catch {
            sendError = "Не удалилось: \(error.localizedDescription)"
        }
    }

    private func loadOlder() async {
        guard !loadingOlder, hasMoreHistory else { return }
        loadingOlder = true
        let loaded = await client.loadOlderMessages(chat.id)
        // Если сервер вернул 0 новых — больше нечего грузить
        if loaded == 0 { hasMoreHistory = false }
        loadingOlder = false
    }

    private func sendFile(data: Data, name: String, mime: String) async {
        do {
            try await client.sendFile(data: data, filename: name, mimeType: mime, to: chat.id)
        } catch {
            sendError = "Файл не ушёл: \(error.localizedDescription)"
        }
    }
}

struct Bubble: View {
    let message: Message
    let isMine: Bool
    var highlighted: Bool = false
    var onReply: (() -> Void)?
    var onForward: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    var onReact: ((String) -> Void)?
    var onTapQuote: (() -> Void)?
    var onTapForward: (() -> Void)?

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 3) {
                if !isMine, !message.senderName.isEmpty {
                    Text(message.senderName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                if let q = message.quote {
                    Button {
                        onTapQuote?()
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(q.author).font(.caption2.weight(.semibold))
                            Text(q.text).font(.caption2).lineLimit(2)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(onTapQuote == nil)
                }
                if let fwd = message.forwardedFrom {
                    Button {
                        onTapForward?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrowshape.turn.up.forward")
                                .font(.caption2)
                            Text("Переслано: \(fwd.author)")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(onTapForward == nil)
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 16 * appearanceManager.fontSize.scale))
                }
                ForEach(message.attachments) { att in
                    AttachmentView(attachment: att)
                }
                if !message.reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(message.reactions) { r in
                            Button {
                                onReact?(r.emoji)
                            } label: {
                                Text("\(r.emoji) \(r.count)")
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(
                                        r.emoji == message.yourReaction
                                            ? Color.accentColor.opacity(0.3)
                                            : Color.primary.opacity(0.08),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text(Self.time.string(from: message.date) + (message.edited ? " · изм." : ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                isMine ? AppearanceManager.shared.bubbleColor.color.opacity(0.22) : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: highlighted ? 2 : 0)
            )
            .contextMenu { menu }
            if !isMine { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder private var menu: some View {
        if let raw = message.rawJSON {
            Button(action: {
                UIPasteboard.general.string = raw
            }) {
                Label("Debug JSON", systemImage: "doc.text")
            }
            Divider()
        }
        if let onReact {
            Menu("Реакция") {
                ForEach(quickReactions, id: \.self) { e in
                    Button(e) { onReact(e) }
                }
            }
        }
        if let onReply { Button { onReply() } label: { Label("Ответить", systemImage: "arrowshape.turn.up.left") } }
        if let onForward { Button { onForward() } label: { Label("Переслать", systemImage: "arrowshape.turn.up.right") } }
        if !message.text.isEmpty {
            Button {
                UIPasteboard.general.string = message.text
            } label: { Label("Копировать", systemImage: "doc.on.doc") }
        }
        if let onEdit { Button { onEdit() } label: { Label("Изменить", systemImage: "pencil") } }
        if let onDelete { Button(role: .destructive) { onDelete() } label: { Label("Удалить", systemImage: "trash") } }
    }
}

/// Фото и видео — целиком, с просмотром на весь экран и сохранением в
/// галерею по долгому нажатию. Стикеры — просто картинкой. Голосовые —
/// проигрываются прямо в сообщении. Остальное — ссылкой.
struct AttachmentView: View {
    let attachment: Attachment
    @ObservedObject private var settings = AppSettings.shared
    @State private var showViewer = false
    @State private var saving = false
    @State private var saveError: String?
    private var saveErrorBinding: Binding<Bool> {
        Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
    }
    @State private var savedOK = false

    private var maxWidth: CGFloat { attachment.kind == .sticker ? 140 : 230 }

    var body: some View {
        switch attachment.kind {
        case .sticker:
            if settings.showImages, let url = attachment.url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit()
                    case .failure: caption("не загрузилось")
                    default:
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.tertiarySystemFill))
                            .aspectRatio(attachment.aspect, contentMode: .fit)
                            .overlay(ProgressView())
                    }
                }
                .frame(maxWidth: maxWidth)
                .padding(.vertical, 2)
            } else {
                caption(attachment.label)
            }

        case .photo, .video:
            if let url = attachment.url {
                mediaThumb(url: url, isVideo: attachment.kind == .video)
            } else {
                caption(attachment.label)
            }

        case .voice:
            if let url = attachment.url {
                VoicePlayerView(url: url, durationHint: attachment.duration)
            } else {
                caption(attachment.label)
            }

        case .file, .call, .share, .other:
            if let url = attachment.url {
                Link(destination: url) {
                    Text("📎 " + attachment.label).font(.caption)
                }
            } else {
                caption(attachment.label)
            }

        case .control:
            EmptyView()
        }
    }

    @ViewBuilder
    private func mediaThumb(url: URL, isVideo: Bool) -> some View {
        Button { showViewer = true } label: {
            Group {
                if !settings.showImages {
                    caption(isVideo ? "видео" : "фото")
                } else if isVideo {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.85))
                            .aspectRatio(attachment.aspect > 0 ? attachment.aspect : 16.0/9.0, contentMode: .fit)
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                    }
                } else {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFit()
                        case .failure: caption("не загрузилось")
                        default:
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.tertiarySystemFill))
                                .aspectRatio(attachment.aspect, contentMode: .fit)
                                .overlay(ProgressView())
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: maxWidth)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                Task { await save(url: url, isVideo: isVideo) }
            } label: {
                Label(savedOK ? "Сохранено" : "Сохранить в Фото",
                     systemImage: savedOK ? "checkmark" : "square.and.arrow.down")
            }
        }
        .overlay(alignment: .topTrailing) {
            if saving { ProgressView().padding(6) }
        }
        .sheet(isPresented: $showViewer) {
            MediaViewer(url: url, isVideo: isVideo)
        }
        .alert("Не сохранилось", isPresented: saveErrorBinding) {
            Button("ОК") { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private func save(url: URL, isVideo: Bool) async {
        saving = true
        defer { saving = false }
        do {
            if isVideo { try await MediaSaver.saveVideo(from: url) }
            else { try await MediaSaver.savePhoto(from: url) }
            savedOK = true
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func caption(_ t: String) -> some View {
        Text("📎 " + t).font(.caption).foregroundStyle(.secondary)
    }
}

struct ThemeToggleButton: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        Button {
            switch themeManager.currentTheme {
            case .light: themeManager.currentTheme = .dark
            case .dark, .amoled: themeManager.currentTheme = .light
            case .system: themeManager.currentTheme = .dark
            }
        } label: {
            Image(systemName: themeManager.currentTheme.colorScheme == .dark ? "sun.max.fill" : "moon.fill")
        }
    }
}
