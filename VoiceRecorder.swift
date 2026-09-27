import Foundation
import AVFoundation

/// Запись голосового: AAC/.m4a, моно, 32 кбит — компактно и совместимо.
@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startedAt: Date?

    enum RecorderError: LocalizedError {
        case denied, failed
        var errorDescription: String? {
            switch self {
            case .denied: return "Нет разрешения на микрофон. Включите его в Настройках iOS."
            case .failed: return "Не получилось начать запись."
            }
        }
    }

    func start() async throws {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { throw RecorderError.denied }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.defaultToSpeaker])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.isMeteringEnabled = false
        guard r.record() else { throw RecorderError.failed }

        recorder = r
        startedAt = Date()
        elapsed = 0
        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let startedAt else { return }
        elapsed = Date().timeIntervalSince(startedAt)
    }

    /// Возвращает файл и длительность, или nil если запись отменена/была пуста.
    func stop() -> (url: URL, duration: TimeInterval)? {
        timer?.invalidate(); timer = nil
        guard let r = recorder else { isRecording = false; return nil }
        let duration = elapsed
        r.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard duration > 0.4 else {
            try? FileManager.default.removeItem(at: r.url)
            return nil
        }
        return (r.url, duration)
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        if let r = recorder {
            r.stop()
            try? FileManager.default.removeItem(at: r.url)
        }
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
