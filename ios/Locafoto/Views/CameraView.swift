import SwiftUI
import AVFoundation

struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()

    var body: some View {
        NavigationView {
            ZStack {
                // Camera Preview
                if viewModel.isCameraReady {
                    CameraPreviewView(session: viewModel.captureSession)
                        .ignoresSafeArea()

                    VStack {
                        Spacer()

                        // Ultra-modern capture button
                        Button(action: {
                            Task {
                                await viewModel.capturePhoto()
                            }
                        }) {
                            ZStack {
                                // Outer pulsing ring
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.locafotoNeon, Color.locafotoPrimary],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 3
                                    )
                                    .frame(width: 90, height: 90)
                                    .blur(radius: 2)

                                // Main gradient button
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.locafotoAccent, Color.locafotoPrimary],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 75, height: 75)
                                    .neonGlow(color: .locafotoNeon, radius: 20)

                                // Inner white circle
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 60, height: 60)

                                // Camera icon
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.locafotoPrimary, .locafotoAccent],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                        }
                        .scaleEffect(viewModel.isCapturing ? 0.9 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.isCapturing)
                        .padding(.bottom, 40)
                        .disabled(viewModel.isCapturing)
                    }
                } else {
                    // Camera not ready - show message
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color.locafotoLight)
                                .frame(width: 120, height: 120)
                            Image(systemName: "camera.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.locafotoPrimary)
                        }
                        Text("Camera Unavailable")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(viewModel.cameraStatusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        if viewModel.needsPermission {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.locafotoPrimary)
                        }
                    }
                }

                // Status overlay
                if viewModel.isCapturing {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()

                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("Encrypting photo...")
                            .foregroundColor(.white)
                            .padding(.top)
                    }
                }
            }
            .navigationTitle("Camera")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Photo Saved", isPresented: $viewModel.showSuccessAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your photo has been encrypted and saved securely.")
            }
            .alert("Error", isPresented: $viewModel.showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "Failed to capture photo")
            }
            .onAppear {
                Task {
                    await viewModel.checkPermissions()
                    await viewModel.startCamera()
                }
            }
            .onDisappear {
                viewModel.stopCamera()
            }
        }
    }
}

/// Camera preview layer using UIViewRepresentable
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // The preview layer automatically resizes with the view
    }

    class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            videoPreviewLayer.videoGravity = .resizeAspectFill
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

#Preview {
    CameraView()
}
