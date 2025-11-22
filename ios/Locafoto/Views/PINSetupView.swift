import SwiftUI

struct PINSetupView: View {
    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var isCreating = false

    let onPINSet: (String) async -> Void

    var body: some View {
        ZStack {
            // Adaptive background for dark/light mode
            Color(.systemBackground)
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
                                .strokeBorder(
                                    LinearGradient(
                                        colors: pin.isEmpty ? [Color.gray.opacity(0.3), Color.gray.opacity(0.3)] : [Color.locafotoPrimary, Color.locafotoAccent],
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
                                .strokeBorder(
                                    LinearGradient(
                                        colors: confirmPin.isEmpty ? [Color.gray.opacity(0.3), Color.gray.opacity(0.3)] : [Color.locafotoPrimary, Color.locafotoAccent],
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
    }

    private var isValidPIN: Bool {
        !pin.isEmpty && pin.count >= 4 && pin == confirmPin
    }

    private func setupPIN() async {
        guard isValidPIN else {
            ToastManager.shared.showError("PINs must match and be at least 4 digits")
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
    @State private var hasAttemptedFaceID = false
    @EnvironmentObject var appState: AppState

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

                Image(systemName: appState.isFaceIDEnabled ? "faceid" : "lock.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
            }

            Text(appState.isFaceIDEnabled ? "Face ID" : "Enter PIN")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Unlock your encrypted files")
                .font(.body)
                .foregroundColor(.secondary)

            // Show pending imports indicator
            if appState.pendingImportCount > 0 {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.locafotoAccent)
                    Text("\(appState.pendingImportCount) file(s) waiting to import")
                        .font(.caption)
                        .foregroundColor(.locafotoAccent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.locafotoAccent.opacity(0.1))
                .cornerRadius(8)
            }

            // Face ID button when enabled
            if appState.isFaceIDEnabled {
                Button(action: {
                    Task {
                        await unlockWithFaceID()
                    }
                }) {
                    HStack {
                        Image(systemName: "faceid")
                            .font(.system(size: 24))
                        Text("Unlock with Face ID")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundColor(.white)
                .background(Color.locafotoPrimary)
                .cornerRadius(10)
                .padding(.horizontal, 40)
                .disabled(isUnlocking)

                Text("or enter PIN")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

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
                    Text("Unlock with PIN")
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
        .onAppear {
            // Auto-trigger Face ID on appear (only once)
            if appState.isFaceIDEnabled && !hasAttemptedFaceID {
                hasAttemptedFaceID = true
                Task {
                    // Small delay to let the view fully appear
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    await unlockWithFaceID()
                }
            }
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

    private func unlockWithFaceID() async {
        isUnlocking = true
        showError = false

        let success = await appState.unlockWithFaceID()

        isUnlocking = false

        if !success {
            // Face ID failed, user can try PIN
            showError = false // Don't show error for Face ID failure
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
    .environmentObject(AppState())
}
