import Foundation
import AVFoundation
import CallKit

/// Управление звонками MAX через WebRTC.
/// Опкоды для звонков нужно найти в протоколе — типичные: CALL_INIT, CALL_ANSWER, CALL_DECLINE, CALL_HANGUP
@MainActor
final class CallManager: NSObject, ObservableObject {

    @Published private(set) var incomingCall: IncomingCall?
    @Published private(set) var activeCall: ActiveCall?

    struct IncomingCall {
        let callId: String
        let fromUserId: Int64
        let fromUserName: String
        let isVideo: Bool
    }

    struct ActiveCall {
        let callId: String
        let userId: Int64
        let userName: String
        let isVideo: Bool
        let isOutgoing: Bool
        var isMuted = false
        var isSpeaker = false
        var isVideoEnabled = false
    }

    private weak var client: MaxClient?
    private var audioSession = AVAudioSession.sharedInstance()

    // TODO: WebRTC peer connection когда найдем опкоды
    // private var peerConnection: RTCPeerConnection?

    init(client: MaxClient) {
        self.client = client
        super.init()
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [])
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    // MARK: - Исходящий звонок

    func startCall(toUserId: Int64, userName: String, isVideo: Bool) async throws {
        guard activeCall == nil else {
            throw CallError.alreadyInCall
        }

        // Сначала просим сервер: если опкод не поддержан — не показываем
        // фантомный «звонок». Раньше экран с таймером появлялся ДО запроса,
        // и уходил только после ответа сервера.
        try await client?.sendCallInit(callId: UUID().uuidString, toUserId: toUserId, isVideo: isVideo)
    }

    // MARK: - Входящий звонок

    func receiveIncomingCall(callId: String, fromUserId: Int64, fromUserName: String, isVideo: Bool) {
        incomingCall = IncomingCall(
            callId: callId,
            fromUserId: fromUserId,
            fromUserName: fromUserName,
            isVideo: isVideo
        )
    }

    func answerCall() async throws {
        guard let incoming = incomingCall else { return }

        try await client?.sendCallAnswer(callId: incoming.callId)

        activeCall = ActiveCall(
            callId: incoming.callId,
            userId: incoming.fromUserId,
            userName: incoming.fromUserName,
            isVideo: incoming.isVideo,
            isOutgoing: false
        )
        incomingCall = nil
    }

    func declineCall() async {
        guard let incoming = incomingCall else { return }
        incomingCall = nil

        try? await client?.sendCallDecline(callId: incoming.callId)
    }

    func endCall() async {
        guard let active = activeCall else { return }
        activeCall = nil

        try? await client?.sendCallHangup(callId: active.callId)

        try? audioSession.setActive(false)
    }

    // MARK: - Управление звонком

    func toggleMute() {
        guard activeCall != nil else { return }
        activeCall?.isMuted.toggle()
        // TODO: Обновить состояние микрофона в WebRTC
    }

    func toggleSpeaker() {
        guard activeCall != nil else { return }
        activeCall?.isSpeaker.toggle()

        do {
            if activeCall?.isSpeaker == true {
                try audioSession.overrideOutputAudioPort(.speaker)
            } else {
                try audioSession.overrideOutputAudioPort(.none)
            }
        } catch {
            print("Failed to toggle speaker: \(error)")
        }
    }

    func toggleVideo() {
        guard activeCall?.isVideo == true else { return }
        activeCall?.isVideoEnabled.toggle()
        // TODO: Обновить состояние камеры в WebRTC
    }

    enum CallError: LocalizedError {
        case alreadyInCall
        case noActiveCall
        case webrtcFailed

        var errorDescription: String? {
            switch self {
            case .alreadyInCall: return "Уже идет звонок"
            case .noActiveCall: return "Нет активного звонка"
            case .webrtcFailed: return "Ошибка соединения"
            }
        }
    }
}
