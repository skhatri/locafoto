import SwiftUI
import AVFoundation

struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()

    var body: some View {
        NavigationView {
            ZStack {
                // Camera Preview
                CameraPreviewView(session: viewModel.captureSession)
                    .ignoresSafeArea()

                VStack {
                    Spacer()

                    // Capture Button
                    Button(action: {
                        Task {
                            await viewModel.capturePhoto()
                        }
                    }) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 70, height: 70)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                                    .frame(width: 80, height: 80)
                            )
                    }
                    .padding(.bottom, 40)
                    .disabled(viewModel.isCapturing)
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

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        // Store the layer in the view for later access
        view.tag = 999

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
        }
    }
}

#Preview {
    CameraView()
}
