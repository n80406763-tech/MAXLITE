import Foundation
import Photos
import UIKit

/// Сохранение фото и видео из чата в галерею. Просит только "добавление"
/// (NSPhotoLibraryAddUsageDescription) — доступ на чтение всей галереи
/// приложению не нужен.
enum MediaSaver {
    enum SaveError: LocalizedError {
        case denied, downloadFailed, saveFailed

        var errorDescription: String? {
            switch self {
            case .denied: return "Нет разрешения на добавление в Фото. Включите его в Настройках iOS."
            case .downloadFailed: return "Не получилось скачать файл."
            case .saveFailed: return "Фото сохранить не удалось."
            }
        }
    }

    private static func ensureAuthorized() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }
    }

    static func savePhoto(from url: URL) async throws {
        try await ensureAuthorized()

        var request = URLRequest(url: url)
        request.setValue("https://web.max.ru", forHTTPHeaderField: "Origin")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
                        forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let image = UIImage(data: data) else { throw SaveError.downloadFailed }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

    static func saveVideo(from url: URL) async throws {
        try await ensureAuthorized()

        let (tmpURL, response) = try await URLSession.shared.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SaveError.downloadFailed
        }

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: dest)

        do {
            try FileManager.default.moveItem(at: tmpURL, to: dest)
        } catch {
            throw SaveError.downloadFailed
        }

        defer { try? FileManager.default.removeItem(at: dest) }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: dest)
        }
    }
}
