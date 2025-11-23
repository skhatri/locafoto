import SwiftUI

// MARK: - Private Album PIN Setup View

struct PrivateAlbumPINSetupView: View {
    @Environment(\.dismiss) var dismiss
    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var step = 1
    @State private var error: String?

    let onComplete: (String) -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.locafotoPrimary)

                    Text(step == 1 ? "Create PIN" : "Confirm PIN")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(step == 1 ? "Enter a 4-8 digit PIN to protect your private albums" : "Re-enter your PIN to confirm")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // PIN dots
                HStack(spacing: 16) {
                    ForEach(0..<8, id: \.self) { index in
                        Circle()
                            .fill(index < currentPIN.count ? Color.locafotoPrimary : Color.gray.opacity(0.3))
                            .frame(width: 16, height: 16)
                    }
                }
                .padding(.vertical)

                // Error message
                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                // Number pad
                VStack(spacing: 16) {
                    ForEach(0..<3) { row in
                        HStack(spacing: 24) {
                            ForEach(1...3, id: \.self) { col in
                                let number = row * 3 + col
                                NumberButton(number: "\(number)") {
                                    appendDigit("\(number)")
                                }
                            }
                        }
                    }

                    HStack(spacing: 24) {
                        // Empty space
                        Color.clear.frame(width: 70, height: 70)

                        NumberButton(number: "0") {
                            appendDigit("0")
                        }

                        // Delete button
                        Button(action: deleteDigit) {
                            Image(systemName: "delete.left.fill")
                                .font(.title2)
                                .foregroundColor(.primary)
                                .frame(width: 70, height: 70)
                        }
                    }
                }

                Spacer()

                // Action buttons
                if currentPIN.count >= 4 {
                    Button(action: nextStep) {
                        Text(step == 1 ? "Next" : "Confirm")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.locafotoPrimary)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
            .navigationTitle("Set Up PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var currentPIN: String {
        step == 1 ? pin : confirmPin
    }

    private func appendDigit(_ digit: String) {
        error = nil
        if step == 1 {
            if pin.count < 8 {
                pin += digit
            }
        } else {
            if confirmPin.count < 8 {
                confirmPin += digit
            }
        }
    }

    private func deleteDigit() {
        if step == 1 {
            if !pin.isEmpty {
                pin.removeLast()
            }
        } else {
            if !confirmPin.isEmpty {
                confirmPin.removeLast()
            }
        }
    }

    private func nextStep() {
        if step == 1 {
            step = 2
        } else {
            if pin == confirmPin {
                onComplete(pin)
                dismiss()
            } else {
                error = "PINs don't match. Try again."
                confirmPin = ""
            }
        }
    }
}

// MARK: - PIN Entry View

struct PINEntryView: View {
    @Environment(\.dismiss) var dismiss
    @State private var pin = ""
    @State private var error: String?
    @State private var attempts = 0
    @State private var isAuthenticated = false

    let albumName: String
    let onVerify: (String) -> Bool
    let onSuccess: () -> Void

    var body: some View {
        NavigationView {
            ZStack {
                if !isAuthenticated {
                    VStack(spacing: 30) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.locafotoPrimary)

                            Text("Enter PIN")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Enter your PIN to access \(albumName)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // PIN dots
                        HStack(spacing: 16) {
                            ForEach(0..<8, id: \.self) { index in
                                Circle()
                                    .fill(index < pin.count ? Color.locafotoPrimary : Color.gray.opacity(0.3))
                                    .frame(width: 16, height: 16)
                            }
                        }
                        .padding(.vertical)

                        // Error message
                        if let error = error {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        // Number pad
                        VStack(spacing: 16) {
                            ForEach(0..<3) { row in
                                HStack(spacing: 24) {
                                    ForEach(1...3, id: \.self) { col in
                                        let number = row * 3 + col
                                        NumberButton(number: "\(number)") {
                                            appendDigit("\(number)")
                                        }
                                    }
                                }
                            }

                            HStack(spacing: 24) {
                                // Empty space
                                Color.clear.frame(width: 70, height: 70)

                                NumberButton(number: "0") {
                                    appendDigit("0")
                                }

                                // Delete button
                                Button(action: deleteDigit) {
                                    Image(systemName: "delete.left.fill")
                                        .font(.title2)
                                        .foregroundColor(.primary)
                                        .frame(width: 70, height: 70)
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding()
                    .transition(.opacity)
                } else {
                    // Translucent "Ready" overlay - onSuccess already called, just need to dismiss sheet
                    AuthenticationReadyOverlay(
                        onDismiss: {
                            dismiss() // Just dismiss, images already loaded
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .interactiveDismissDisabled(false) // Allow drag-down dismissal
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isAuthenticated)
            .navigationTitle("Private Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func appendDigit(_ digit: String) {
        error = nil
        if pin.count < 8 {
            pin += digit
        }

        // Auto-verify when PIN is 4+ digits
        if pin.count >= 4 {
            verifyPIN()
        }
    }

    private func deleteDigit() {
        if !pin.isEmpty {
            pin.removeLast()
        }
    }

    private func verifyPIN() {
        if onVerify(pin) {
            // Call onSuccess immediately to load images behind the overlay
            onSuccess()
            // Then show the transparent overlay for the "peek" effect
            withAnimation {
                isAuthenticated = true
            }
        } else {
            attempts += 1
            error = "Invalid PIN. \(max(0, 5 - attempts)) attempts remaining."
            pin = ""

            if attempts >= 5 {
                dismiss()
            }
        }
    }
}

// MARK: - Number Button

struct NumberButton: View {
    let number: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(number)
                .font(.title)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .frame(width: 70, height: 70)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(35)
        }
    }
}

// MARK: - Authentication Ready Overlay

struct AuthenticationReadyOverlay: View {
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var showCheckmark = false
    @State private var checkmarkScale: CGFloat = 0.5
    @State private var hasCalledOnDismiss = false
    
    var body: some View {
        ZStack {
            // Really transparent blurred background - allows content behind to show through very clearly
            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.15))
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                // Success checkmark with animation
                ZStack {
                    Circle()
                        .fill(Color.locafotoPrimary.opacity(0.15))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.locafotoPrimary)
                        .scaleEffect(showCheckmark ? 1.0 : 0.5)
                        .opacity(showCheckmark ? 1.0 : 0.0)
                }
                .scaleEffect(checkmarkScale)
                
                // "Ready" message
                VStack(spacing: 8) {
                    Text("Ready")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Swipe down to continue")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .opacity(showCheckmark ? 1.0 : 0.0)
                
                Spacer()
            }
            .padding()
        }
        .background(Color.clear) // Ensure background is clear
        .onAppear {
            // Animate checkmark appearance
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                checkmarkScale = 1.0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    showCheckmark = true
                }
            }
        }
        .onDisappear {
            // Call onDismiss when view disappears (drag down)
            handleDismiss()
        }
    }
    
    private func handleDismiss() {
        // Only call once to prevent double-calling
        guard !hasCalledOnDismiss else { return }
        hasCalledOnDismiss = true
        onDismiss()
    }
}

// MARK: - Face ID Prompt View

struct FaceIDPromptView: View {
    let albumName: String
    let onAuthenticate: () async -> Bool
    let onSuccess: () -> Void
    let onCancel: () -> Void

    @State private var isAuthenticating = false
    @State private var isAuthenticated = false
    @State private var error: String?

    var body: some View {
        ZStack {
            // Main authentication view
            if !isAuthenticated {
                VStack(spacing: 30) {
                    Spacer()

                    // Icon
                    Image(systemName: "faceid")
                        .font(.system(size: 80))
                        .foregroundColor(.locafotoPrimary)

                    // Text
                    VStack(spacing: 8) {
                        Text("Face ID Required")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Authenticate to access \(albumName)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let error = error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Spacer()

                    // Buttons
                    VStack(spacing: 12) {
                        Button(action: authenticate) {
                            HStack {
                                if isAuthenticating {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "faceid")
                                }
                                Text("Authenticate")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.locafotoPrimary)
                            .cornerRadius(12)
                        }
                        .disabled(isAuthenticating)

                        Button("Cancel") {
                            onCancel()
                        }
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
                .padding()
                .transition(.opacity)
            } else {
                // Translucent "Ready" overlay
                AuthenticationReadyOverlay(
                    onDismiss: {
                        onSuccess()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .interactiveDismissDisabled(false) // Allow drag-down dismissal
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isAuthenticated)
        .onAppear {
            authenticate()
        }
    }

    private func authenticate() {
        isAuthenticating = true
        error = nil

        Task {
            let success = await onAuthenticate()
            await MainActor.run {
                isAuthenticating = false
                if success {
                    // Call onSuccess immediately to load images behind the overlay
                    onSuccess()
                    // Then show the transparent overlay for the "peek" effect
                    withAnimation {
                        isAuthenticated = true
                    }
                } else {
                    error = "Authentication failed. Try again."
                }
            }
        }
    }
}

// MARK: - Private Album Auth Sheet

struct PrivateAlbumAuthSheet: View {
    let album: Album
    let onSuccess: () -> Void

    @Environment(\.dismiss) var dismiss

    private let biometricService = BiometricService()
    private let pinService = PrivateAlbumPINService()
    private let keyService = PrivateAlbumKeyService()

    var body: some View {
        Group {
            if biometricService.isFaceIDAvailable() && keyService.isProtectedWithFaceID(albumId: album.id) {
                FaceIDPromptView(
                    albumName: album.name,
                    onAuthenticate: authenticateWithFaceID,
                    onSuccess: onSuccess,
                    onCancel: { dismiss() }
                )
            } else {
                PINEntryView(
                    albumName: album.name,
                    onVerify: { pin in
                        pinService.verifyPIN(pin)
                    },
                    onSuccess: onSuccess
                )
            }
        }
    }

    private func authenticateWithFaceID() async -> Bool {
        do {
            _ = try await keyService.getPrivateAlbumKeyWithFaceID(for: album)
            return true
        } catch {
            return false
        }
    }
}

#Preview {
    PrivateAlbumPINSetupView { _ in }
}
