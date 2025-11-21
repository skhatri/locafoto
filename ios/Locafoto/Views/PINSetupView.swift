import SwiftUI

struct PINSetupView: View {
    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""

    let onPINSet: (String) async -> Void

    var body: some View {
        ZStack {
            // Animated gradient background
            LinearGradient(
                colors: [
                    Color.locafotoLight,
                    Color.white,
                    Color.locafotoPurple.opacity(0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 35) {
                Spacer()

                ZStack {
                    // Outer glow rings
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.locafotoNeon, Color.locafotoPrimary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 160, height: 160)
                        .blur(radius: 15)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.locafotoPrimary, Color.locafotoAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)
                        .neonGlow(color: .locafotoPrimary, radius: 20)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 65, weight: .bold))
                        .foregroundColor(.white)
                }
                .floating()

                VStack(spacing: 12) {
                    Text("Secure Your Vault")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.locafotoPrimary, .locafotoAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text("Create a PIN for ultimate privacy ✨")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                VStack(spacing: 16) {
                    SecureField("Enter PIN", text: $pin)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .padding()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(
                                    pin.isEmpty ? Color.gray.opacity(0.3) : LinearGradient(
                                        colors: [Color.locafotoPrimary, Color.locafotoAccent],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: .locafotoPrimary.opacity(pin.isEmpty ? 0 : 0.2), radius: 8, x: 0, y: 4)
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 30)

                    SecureField("Confirm PIN", text: $confirmPin)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .padding()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(
                                    confirmPin.isEmpty ? Color.gray.opacity(0.3) : LinearGradient(
                                        colors: [Color.locafotoPrimary, Color.locafotoAccent],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: .locafotoPrimary.opacity(confirmPin.isEmpty ? 0 : 0.2), radius: 8, x: 0, y: 4)
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 30)
                }

                Button(action: {
                    Task {
                        await setupPIN()
                    }
                }) {
                    HStack(spacing: 12) {
                        if isCreating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 18, weight: .bold))
                            Text("Secure My Vault")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: isValidPIN ? [Color.locafotoPrimary, Color.locafotoAccent] : [Color.gray, Color.gray.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .neonGlow(color: isValidPIN ? .locafotoPrimary : .clear, radius: 15)
                }
                .padding(.horizontal, 30)
                .padding(.top, 10)
                .disabled(!isValidPIN || isCreating)
                .scaleEffect(isValidPIN ? 1.0 : 0.98)
                .animation(.spring(response: 0.3), value: isValidPIN)

                Spacer()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var isValidPIN: Bool {
        !pin.isEmpty && pin.count >= 4 && pin == confirmPin
    }

    private func setupPIN() async {
        guard isValidPIN else {
            errorMessage = "PINs must match and be at least 4 digits"
            showError = true
            return
        }

        isCreating = true
        await onPINSet(pin)
        isCreating = false
    }
}

struct PINUnlockView: View {
    @State private var pin = ""
    @State private var isUnlocking = false
    @State private var showError = false

    let onUnlock: (String) async -> Bool

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.locafotoPrimary, Color.locafotoAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)

                Image(systemName: "lock.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
            }

            Text("Enter PIN")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Unlock your encrypted files")
                .font(.body)
                .foregroundColor(.secondary)

            SecureField("PIN", text: $pin)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.numberPad)
                .padding(.horizontal, 40)
                .onSubmit {
                    Task {
                        await unlock()
                    }
                }

            Button(action: {
                Task {
                    await unlock()
                }
            }) {
                if isUnlocking {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Unlock")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundColor(.white)
            .background(pin.isEmpty ? Color.gray : Color.locafotoPrimary)
            .cornerRadius(10)
            .padding(.horizontal, 40)
            .disabled(pin.isEmpty || isUnlocking)

            if showError {
                Text("Incorrect PIN")
                    .foregroundColor(.locafotoError)
                    .font(.caption)
            }

            Spacer()
        }
    }

    private func unlock() async {
        isUnlocking = true
        showError = false

        let success = await onUnlock(pin)

        isUnlocking = false

        if !success {
            showError = true
            pin = ""
        }
    }
}

#Preview("Setup") {
    PINSetupView { pin in
        print("PIN set: \(pin)")
    }
}

#Preview("Unlock") {
    PINUnlockView { pin in
        return pin == "1234"
    }
}
