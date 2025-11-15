import SwiftUI

struct PINSetupView: View {
    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""

    let onPINSet: (String) async -> Void

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 70))
                .foregroundColor(.blue)

            Text("Set Up PIN")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Create a PIN to secure your encryption keys")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 20) {
                SecureField("Enter PIN", text: $pin)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 40)

                SecureField("Confirm PIN", text: $confirmPin)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 40)
            }

            Button(action: {
                Task {
                    await setupPIN()
                }
            }) {
                if isCreating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Set PIN")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundColor(.white)
            .background(isValidPIN ? Color.blue : Color.gray)
            .cornerRadius(10)
            .padding(.horizontal, 40)
            .disabled(!isValidPIN || isCreating)

            Spacer()
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

            Image(systemName: "lock.fill")
                .font(.system(size: 70))
                .foregroundColor(.blue)

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
            .background(pin.isEmpty ? Color.gray : Color.blue)
            .cornerRadius(10)
            .padding(.horizontal, 40)
            .disabled(pin.isEmpty || isUnlocking)

            if showError {
                Text("Incorrect PIN")
                    .foregroundColor(.red)
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
