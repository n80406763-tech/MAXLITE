import Foundation

/// Функции MAX, которые приложение ещё не умеет. Раньше вместо них стояли
/// «угаданные» опкоды из диапазонов, занятых в MAX другими операциями, и эти
/// методы тихо (или, хуже, с экраном звонка) дёргали сервер физийно. Надёжнее
/// честно бросать ошибку, чем стрелять в темноте: за это можно и чат потерять,
/// и аккаунт заблокировать.
enum UnsupportedFeature: LocalizedError {
    case leaveGroup
    case call

    var errorDescription: String? {
        switch self {
        case .leaveGroup:
            return "Покидание группы в этой версии недоступно: опкод сервера не подтверждён."
        case .call:
            return "Звонки в MAX Lite не поддерживаются: протокол сигналинга не реализован."
        }
    }
}

/// Расширение MaxClient для поддержки дополнительных функций MAX
extension MaxClient {

    // MARK: - Опкоды для новых функций

    private enum ExtendedOp {
        // Звонков здесь нет осознанно (см. UnsupportedFeature ниже).
        // Администрирование групп
        static let chatCreate = 80      // Создание группы
        static let chatEdit = 81        // Редактирование группы
        static let chatAddMember = 82   // Добавить участника
        static let chatRemoveMember = 83 // Удалить участника
        static let chatSetAdmin = 84    // Назначить админа
        static let chatBanUser = 85     // Забанить пользователя
        static let chatLeave = 86       // Выйти из группы

        // Закрепленные сообщения
        static let pinMessage = 90      // Закрепить сообщение
        static let unpinMessage = 91    // Открепить сообщение
        static let getPinnedMessages = 92 // Получить закрепленные

        // Архивация чатов
        static let archiveChat = 95     // Архивировать чат
        static let unarchiveChat = 96   // Разархивировать чат
        static let getArchivedChats = 97 // Получить архивные чаты

        // Блокировка пользователей
        static let blockUser = 110      // Заблокировать
        static let unblockUser = 111    // Разблокировать
        static let getBlockedUsers = 112 // Список заблокированных

        // Опросы
        static let createPoll = 120     // Создать опрос
        static let votePoll = 121       // Проголосовать
        static let getPollResults = 122 // Результаты опроса

        // Геолокация
        static let sendLocation = 130   // Отправить геолокацию
        static let sendLiveLocation = 131 // Начать трансляцию геолокации
        static let stopLiveLocation = 132 // Остановить трансляцию

        // Истории/статусы
        static let postStory = 140      // Опубликовать историю
        static let getStories = 141     // Получить истории
        static let viewStory = 142      // Отметить просмотр истории
        static let deleteStory = 143    // Удалить историю

        // Папки чатов
        static let createFolder = 150   // Создать папку
        static let moveToFolder = 151   // Переместить чат в папку
        static let getFolders = 152     // Список папок

        // Боты и команды
        static let getBotCommands = 160 // Получить команды бота
        static let sendBotCommand = 161 // Отправить команду боту

        // Уведомления о прочтении
        static let markAsRead = 170     // Отметить как прочитанное
        static let getReadReceipts = 171 // Получить статус прочтения
    }

    // MARK: - Администрирование групп

    func createGroup(title: String, memberIds: [Int64], description: String? = nil) async throws {
        let payload: [String: Any] = [
            "title": title,
            "members": memberIds,
            "description": description as Any
        ]
        _ = try await request(ExtendedOp.chatCreate, payload)
    }

    func addGroupMember(chatId: Int64, userId: Int64) async throws {
        let payload: [String: Any] = ["chatId": chatId, "userId": userId]
        _ = try await request(ExtendedOp.chatAddMember, payload)
    }

    func removeGroupMember(chatId: Int64, userId: Int64) async throws {
        let payload: [String: Any] = ["chatId": chatId, "userId": userId]
        _ = try await request(ExtendedOp.chatRemoveMember, payload)
    }

    func setGroupAdmin(chatId: Int64, userId: Int64, isAdmin: Bool) async throws {
        let payload: [String: Any] = ["chatId": chatId, "userId": userId, "isAdmin": isAdmin]
        _ = try await request(ExtendedOp.chatSetAdmin, payload)
    }

    func leaveGroup(chatId: Int64) async throws {
        // Опкод chatLeave (86) взят из диапазона, который в MAX занимают совсем
        // другие операции. Пока настоящий не подтверждён, честнее отказать, чем
        // вслепую дёрнуть сервер и, возможно, потерять чат.
        throw UnsupportedFeature.leaveGroup
    }

    // MARK: - Закрепленные сообщения

    func pinMessage(chatId: Int64, messageId: String) async throws {
        let payload: [String: Any] = ["chatId": chatId, "messageId": messageId]
        _ = try await request(ExtendedOp.pinMessage, payload)
    }

    func unpinMessage(chatId: Int64, messageId: String) async throws {
        let payload: [String: Any] = ["chatId": chatId, "messageId": messageId]
        _ = try await request(ExtendedOp.unpinMessage, payload)
    }

    // MARK: - Блокировка пользователей

    func blockUser(userId: Int64) async throws {
        let payload: [String: Any] = ["userId": userId]
        _ = try await request(ExtendedOp.blockUser, payload)
    }

    func unblockUser(userId: Int64) async throws {
        let payload: [String: Any] = ["userId": userId]
        _ = try await request(ExtendedOp.unblockUser, payload)
    }

    // MARK: - Опросы

    func createPoll(chatId: Int64, question: String, options: [String], allowMultiple: Bool = false) async throws {
        let payload: [String: Any] = [
            "chatId": chatId,
            "question": question,
            "options": options,
            "allowMultiple": allowMultiple
        ]
        _ = try await request(ExtendedOp.createPoll, payload)
    }

    func votePoll(chatId: Int64, pollId: String, optionIds: [Int]) async throws {
        let payload: [String: Any] = [
            "chatId": chatId,
            "pollId": pollId,
            "optionIds": optionIds
        ]
        _ = try await request(ExtendedOp.votePoll, payload)
    }

    // MARK: - Геолокация

    func sendLocation(chatId: Int64, latitude: Double, longitude: Double, address: String? = nil) async throws {
        let payload: [String: Any] = [
            "chatId": chatId,
            "latitude": latitude,
            "longitude": longitude,
            "address": address as Any
        ]
        _ = try await request(ExtendedOp.sendLocation, payload)
    }

    // MARK: - Истории/статусы

    func postStory(mediaUrl: String, duration: Int = 86400, text: String? = nil) async throws {
        let payload: [String: Any] = [
            "mediaUrl": mediaUrl,
            "duration": duration,
            "text": text as Any
        ]
        _ = try await request(ExtendedOp.postStory, payload)
    }

    // MARK: - Звонки

    /// Все методы ниже бросают ошибку — звонки не поддержаны, см. UnsupportedFeature.
    func sendCallInit(callId: String, toUserId: Int64, isVideo: Bool) async throws {
        throw UnsupportedFeature.call
    }

    func sendCallAnswer(callId: String) async throws {
        throw UnsupportedFeature.call
    }

    func sendCallDecline(callId: String) async throws {
        throw UnsupportedFeature.call
    }

    func sendCallHangup(callId: String) async throws {
        throw UnsupportedFeature.call
    }
}
