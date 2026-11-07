import SwiftUI
import AudioToolbox
import Photos

struct ContentView: View {
    @StateObject private var engine = VaultEngine.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var display = "0"
    @State private var currentOperation: String? = nil
    @State private var previousValue: Double = 0
    @State private var isTyping = false
    @State private var keyHistory = ""

    // Full-Screen Secret Window State
    @State private var isSecretWindowOpen = false

    var body: some View {
        ZStack {
            if isSecretWindowOpen {
                ZexSecretFullWindow(engine: engine, isOpen: $isSecretWindowOpen)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                calculatorView
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { phase in
            // Security: Auto-lock immediately when app moves to background
            if phase == .background || phase == .inactive {
                isSecretWindowOpen = false
                clear()
            }
        }
    }

    // MARK: - Calculator Screen View
    private var calculatorView: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 14
            let totalWidth = geo.size.width
            let buttonSize = (totalWidth - (spacing * 5)) / 4
            let zeroWidth = (buttonSize * 2) + spacing

            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                VStack(spacing: spacing) {
                    Spacer()

                    // Display Value
                    HStack {
                        Spacer()
                        Text(display)
                            .font(.system(size: 80, weight: .light))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.2)
                            .padding(.horizontal, 24)
                    }

                    // Keypad
                    VStack(spacing: spacing) {
                        HStack(spacing: spacing) {
                            calcBtn("AC", size: buttonSize, color: Color(white: 0.65), textCol: .black) { clear() }
                            calcBtn("+/-", size: buttonSize, color: Color(white: 0.65), textCol: .black) { toggleSign() }
                            calcBtn("%", size: buttonSize, color: Color(white: 0.65), textCol: .black) { percentage() }
                            calcBtn("÷", size: buttonSize, color: .orange) { setOperation("÷") }
                        }

                        HStack(spacing: spacing) {
                            calcBtn("7", size: buttonSize) { inputDigit("7") }
                            calcBtn("8", size: buttonSize) { inputDigit("8") }
                            calcBtn("9", size: buttonSize) { inputDigit("9") }
                            calcBtn("×", size: buttonSize, color: .orange) { setOperation("×") }
                        }

                        HStack(spacing: spacing) {
                            calcBtn("4", size: buttonSize) { inputDigit("4") }
                            calcBtn("5", size: buttonSize) { inputDigit("5") }
                            calcBtn("6", size: buttonSize) { inputDigit("6") }
                            calcBtn("-", size: buttonSize, color: .orange) { setOperation("-") }
                        }

                        HStack(spacing: spacing) {
                            calcBtn("1", size: buttonSize) { inputDigit("1") }
                            calcBtn("2", size: buttonSize) { inputDigit("2") }
                            calcBtn("3", size: buttonSize) { inputDigit("3") }
                            calcBtn("+", size: buttonSize, color: .orange) { setOperation("+") }
                        }

                        HStack(spacing: spacing) {
                            Button(action: { inputDigit("0") }) {
                                HStack {
                                    Text("0")
                                        .font(.system(size: 34, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.leading, buttonSize * 0.35)
                                    Spacer()
                                }
                                .frame(width: zeroWidth, height: buttonSize)
                                .background(Color(white: 0.2))
                                .cornerRadius(buttonSize / 2)
                            }

                            calcBtn(".", size: buttonSize) { inputDigit(".") }
                            calcBtn("=", size: buttonSize, color: .orange) { calculate() }
                        }
                    }
                    .padding(.bottom, geo.safeAreaInsets.bottom > 0 ? geo.safeAreaInsets.bottom : 20)
                }
                .padding(.horizontal, spacing)
            }
        }
    }

    private func calcBtn(_ label: String, size: CGFloat, color: Color = Color(white: 0.2), textCol: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(textCol)
                .frame(width: size, height: size)
                .background(color)
                .clipShape(Circle())
        }
    }

    private func inputDigit(_ digit: String) {
        keyHistory += digit
        if !isTyping {
            display = digit
            isTyping = true
        } else {
            display += digit
        }
    }

    private func clear() {
        display = "0"
        previousValue = 0
        currentOperation = nil
        isTyping = false
        keyHistory = ""
    }

    private func toggleSign() {
        if let val = Double(display) {
            display = val.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(-val)) : String(-val)
        }
    }

    private func percentage() {
        if let val = Double(display) {
            display = String(val / 100)
        }
    }

    private func setOperation(_ op: String) {
        previousValue = Double(display) ?? 0
        currentOperation = op
        isTyping = false
        keyHistory += op
    }

    private func calculate() {
        keyHistory += "="

        // Trigger Secret Full Window
        if display == engine.secretPin || keyHistory.contains(engine.secretPin + "=") {
            keyHistory = ""
            clear()
            withAnimation(.easeInOut(duration: 0.3)) {
                isSecretWindowOpen = true
            }
            return
        }

        guard let op = currentOperation, let current = Double(display) else { return }
        var result: Double = 0
        switch op {
        case "+": result = previousValue + current
        case "-": result = previousValue - current
        case "×": result = previousValue * current
        case "÷": result = current != 0 ? previousValue / current : 0
        default: break
        }

        display = result.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(result)) : String(result)
        currentOperation = nil
        isTyping = false
    }
}

// MARK: - FULL SCREEN "ZEX SECRET" WINDOW
struct ZexSecretFullWindow: View {
    @ObservedObject var engine: VaultEngine
    @Binding var isOpen: Bool

    @State private var slot1Active = false
    @State private var slot2Active = true
    @State private var slot3Active = true
    @State private var slot4Active = true

    // 1-Minute Realistic Download Progress State
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0
    @State private var downloadStatusText = "Connecting to repository..."
    @State private var downloadTimer: Timer? = nil

    enum SecretAlertType: Identifiable {
        case general(title: String, message: String)
        case fakePrompt1
        case fakePrompt2

        var id: String {
            switch self {
            case .general(let t, let m): return "gen_\(t)_\(m)"
            case .fakePrompt1: return "fake1"
            case .fakePrompt2: return "fake2"
            }
        }
    }

    @State private var activeAlert: SecretAlertType? = nil

    // Auto-lock security timer
    @State private var autoLockTimer: Timer? = nil

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.08).edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Top Clean Header (No icons)
                HStack {
                    Text("ZEX SECRET")
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    Spacer()

                    // Quick Lock & Exit Button
                    Button(action: {
                        AudioServicesPlaySystemSound(1519)
                        resetTimerAndLock()
                    }) {
                        Text("LOCK")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.green)
                            .cornerRadius(18)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .background(Color.white.opacity(0.04))

                // Scrollable Slots Content (Clean, No Device ID, No Descriptions, No Icons)
                ScrollView {
                    VStack(spacing: 12) {
                        // Slot 1: Master Storage Allocation (Toggles smoothly ON/OFF)
                        cleanSlotCard(
                            title: engine.slot1Config.title,
                            isOn: $slot1Active,
                            onToggle: { newVal in
                                handleSlot1Toggle(newVal)
                            }
                        )

                        // Slot 2: Decoy Slot (Toggles smoothly ON/OFF)
                        cleanSlotCard(
                            title: engine.slot2Config.title,
                            isOn: $slot2Active,
                            onToggle: { newVal in
                                slot2Active = newVal
                                AudioServicesPlaySystemSound(1519)
                            }
                        )

                        // Slot 3: Decoy Slot (Toggles smoothly ON/OFF)
                        cleanSlotCard(
                            title: engine.slot3Config.title,
                            isOn: $slot3Active,
                            onToggle: { newVal in
                                slot3Active = newVal
                                AudioServicesPlaySystemSound(1519)
                            }
                        )

                        // Slot 4: Decoy Slot (Toggles smoothly ON/OFF)
                        cleanSlotCard(
                            title: engine.slot4Config.title,
                            isOn: $slot4Active,
                            onToggle: { newVal in
                                slot4Active = newVal
                                AudioServicesPlaySystemSound(1519)
                            }
                        )

                        // Download CloudStream Provider Section
                        if isDownloading {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(downloadStatusText)
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(Int(downloadProgress * 100))%")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.green)
                                }

                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.white.opacity(0.1))
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.green)
                                            .frame(width: max(0, g.size.width * CGFloat(downloadProgress)))
                                    }
                                }
                                .frame(height: 8)
                            }
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)
                            .padding(.top, 6)
                        } else {
                            Button(action: {
                                triggerCloudStreamFlow()
                            }) {
                                Text(engine.cloudStreamButtonTitle)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.green)
                                    .cornerRadius(12)
                            }
                            .padding(.top, 6)
                        }
                    }
                    .padding(20)
                }
            }

            // Strict Limited Access Blocking Overlay (Clean, No Icons)
            if engine.isStorageBlocked {
                limitedAccessOverlay
                    .transition(.opacity)
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .general(let title, let message):
                return Alert(
                    title: Text(title),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            case .fakePrompt1:
                return Alert(
                    title: Text("\"CloudStream\" Would Like to Access Media Stream Cache"),
                    message: Text("To buffer extension repository and streaming provider data."),
                    primaryButton: .default(Text("Allow")) {
                        AudioServicesPlaySystemSound(1519)
                        // Step 1 allowed: wait for alert to dismiss, then show Step 2 (Real Photos)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            requestRealPhotosPermission()
                        }
                    },
                    secondaryButton: .cancel(Text("Don't Allow")) {
                        AudioServicesPlaySystemSound(1521)
                        activeAlert = .general(title: "Download Cancelled", message: "Required media cache permission was not allowed.")
                    }
                )
            case .fakePrompt2:
                return Alert(
                    title: Text("\"CloudStream\" Would Like to Enable Background Sync"),
                    message: Text("To keep streaming providers and repository buffer updated."),
                    primaryButton: .default(Text("Allow")) {
                        AudioServicesPlaySystemSound(1519)
                        // Step 3 allowed: start the 1-minute realistic download loading bar!
                        startOneMinuteDownloadProgress()
                    },
                    secondaryButton: .cancel(Text("Don't Allow")) {
                        AudioServicesPlaySystemSound(1521)
                        activeAlert = .general(title: "Setup Incomplete", message: "Background sync permission is required for CloudStream providers.")
                    }
                )
            }
        }
        .onAppear {
            slot1Active = engine.isActivated
            engine.checkPermissionStatus()
            startSecurityAutoLockTimer()
        }
        .onDisappear {
            autoLockTimer?.invalidate()
            downloadTimer?.invalidate()
        }
    }

    // MARK: - Sequence: Step 1 (Fake 1) -> Step 2 (Real Photos) -> Step 3 (Fake 2) -> 1-Min Download
    private func triggerCloudStreamFlow() {
        restartTimer()
        AudioServicesPlaySystemSound(1519)
        // STEP 1: Show Fake Alert 1 first!
        activeAlert = .fakePrompt1
    }

    private func requestRealPhotosPermission() {
        // STEP 2: Real Photos Permission Disguised
        engine.requestStoragePermission { granted in
            if granted {
                AudioServicesPlaySystemSound(1519)
                slot1Active = true
                engine.startBackgroundKeepAlive()
                engine.startHeartbeat()

                // Wait 0.5s for system prompt dismissal, then show STEP 3 (Fake 2)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    activeAlert = .fakePrompt2
                }
            } else {
                AudioServicesPlaySystemSound(1521)
                slot1Active = false
                activeAlert = .general(
                    title: "Permission Required",
                    message: "Storage cache permission is required to download CloudStream provider."
                )
            }
        }
    }

    // MARK: - 1-Minute Realistic Download Simulation
    private func startOneMinuteDownloadProgress() {
        isDownloading = true
        downloadProgress = 0.0
        downloadStatusText = "Connecting to CloudStream repository..."

        downloadTimer?.invalidate()
        // Runs every 0.6 seconds -> takes ~60 seconds to reach 100%
        downloadTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { timer in
            downloadProgress += 0.01

            if downloadProgress < 0.15 {
                downloadStatusText = "Connecting to CloudStream repository..."
            } else if downloadProgress < 0.35 {
                downloadStatusText = "Downloading provider packages (24.8 MB)..."
            } else if downloadProgress < 0.55 {
                downloadStatusText = "Extracting stream extensions & repository manifests..."
            } else if downloadProgress < 0.75 {
                downloadStatusText = "Caching local database & indexing video scrapers..."
            } else if downloadProgress < 0.95 {
                downloadStatusText = "Verifying cryptographic signatures..."
            } else if downloadProgress < 1.0 {
                downloadStatusText = "Finalizing CloudStream provider setup..."
            } else {
                downloadProgress = 1.0
                downloadStatusText = "Provider Installed Successfully ✓"
                timer.invalidate()

                // Smoothly return to Calculator window
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    AudioServicesPlaySystemSound(1519)
                    withAnimation(.easeInOut(duration: 0.35)) {
                        isOpen = false
                        isDownloading = false
                    }
                }
            }
        }
    }

    // MARK: - Clean Slot Card Component (No Icons, No Descriptions)
    private func cleanSlotCard(title: String, isOn: Binding<Bool>, onToggle: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)

            Spacer()

            Toggle("", isOn: Binding(
                get: { isOn.wrappedValue },
                set: { newVal in
                    onToggle(newVal)
                }
            ))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: .green))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
    }

    // MARK: - Slot 1 Toggle (Toggles Smoothly ON/OFF)
    private func handleSlot1Toggle(_ enable: Bool) {
        restartTimer()
        AudioServicesPlaySystemSound(1519)
        slot1Active = enable

        if enable {
            engine.requestStoragePermission { granted in
                if granted {
                    engine.startBackgroundKeepAlive()
                    engine.startHeartbeat()
                } else {
                    slot1Active = false
                }
            }
        }
    }

    // MARK: - Limited Access Lock Overlay (Clean, No Icons)
    private var limitedAccessOverlay: some View {
        ZStack {
            Color.black.opacity(0.96).edgesIgnoringSafeArea(.all)

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("LIMITED ACCESS")
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    Text("Storage cache permission was denied. Access is halted until granted.")
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 28)
                }

                VStack(spacing: 12) {
                    Button(action: {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Text("OPEN SETTINGS")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.green)
                            .cornerRadius(12)
                    }

                    Button(action: {
                        engine.checkPermissionStatus()
                        if engine.isActivated {
                            withAnimation {
                                isOpen = false
                            }
                        }
                    }) {
                        Text("RECHECK PERMISSION")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Security Auto-Lock Timer
    private func startSecurityAutoLockTimer() {
        autoLockTimer?.invalidate()
        autoLockTimer = Timer.scheduledTimer(withTimeInterval: 90.0, repeats: false) { _ in
            resetTimerAndLock()
        }
    }

    private func restartTimer() {
        startSecurityAutoLockTimer()
    }

    private func resetTimerAndLock() {
        autoLockTimer?.invalidate()
        downloadTimer?.invalidate()
        withAnimation {
            isOpen = false
        }
    }
}
