import SwiftUI
import AVFoundation

struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()
    @EnvironmentObject var appState: AppState
    @Binding var selectedTab: Int

    init(selectedTab: Binding<Int> = .constant(1)) {
        self._selectedTab = selectedTab
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Camera Preview
                if viewModel.isCameraReady {
                    FilteredPreviewView(
                        currentFilter: $viewModel.selectedFilter,
                        viewModel: viewModel
                    )
                    .ignoresSafeArea()

                    VStack {
                        // Top controls: album selector and flip button
                        HStack {
                            // Flip camera button
                            Button(action: {
                                Task {
                                    await viewModel.flipCamera()
                                }
                            }) {
                                Image(systemName: "camera.rotate.fill")
                                    .font(.title2)
                                    .padding(12)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .padding()

                            Spacer()

                            // Album selector (album determines the key)
                            if !viewModel.availableAlbums.isEmpty {
                                Menu {
                                    ForEach(viewModel.availableAlbums) { album in
                                        Button(action: {
                                            viewModel.selectedAlbumId = album.id
                                            viewModel.selectedKeyName = album.keyName
                                        }) {
                                            HStack {
                                                VStack(alignment: .leading) {
                                                    Text(album.name)
                                                    Text(album.keyName)
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                                if viewModel.selectedAlbumId == album.id {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "rectangle.stack.fill")
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(viewModel.selectedAlbum?.name ?? "Select Album")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                            if let keyName = viewModel.selectedKeyName {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "key.fill")
                                                        .font(.system(size: 8))
                                                    Text(keyName)
                                                        .font(.system(size: 10))
                                                }
                                                .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(20)
                                }
                                .padding()
                            }
                        }

                        Spacer()

                        // Mode toggle (Photo/Video)
                        HStack(spacing: 0) {
                            ForEach(CaptureMode.allCases, id: \.self) { mode in
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewModel.captureMode = mode
                                    }
                                }) {
                                    Text(mode.rawValue)
                                        .font(.system(size: 14, weight: .semibold))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            viewModel.captureMode == mode
                                                ? Color.locafotoPrimary
                                                : Color.clear
                                        )
                                        .foregroundColor(
                                            viewModel.captureMode == mode
                                                ? .white
                                                : .white.opacity(0.7)
                                        )
                                        .cornerRadius(20)
                                }
                                .disabled(viewModel.isRecording)
                            }
                        }
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        .padding(.bottom, 10)

                        // Filter selector
                        if viewModel.captureMode == .photo {
                            // Photo filters
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(CameraFilterPreset.allCases) { preset in
                                        Button(action: {
                                            viewModel.selectedFilter = preset
                                        }) {
                                            VStack(spacing: 4) {
                                                Image(systemName: preset.icon)
                                                    .font(.system(size: 20))
                                                Text(preset.rawValue)
                                                    .font(.caption2)
                                            }
                                            .frame(width: 60, height: 50)
                                            .background(
                                                viewModel.selectedFilter == preset
                                                    ? Color.locafotoPrimary.opacity(0.8)
                                                    : Color.black.opacity(0.3)
                                            )
                                            .foregroundColor(.white)
                                            .cornerRadius(10)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .padding(.bottom, 20)
                        } else {
                            // Video filters
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(VideoFilterPreset.allCases) { preset in
                                        Button(action: {
                                            viewModel.selectedVideoFilter = preset
                                        }) {
                                            VStack(spacing: 4) {
                                                Image(systemName: preset.icon)
                                                    .font(.system(size: 20))
                                                Text(preset.rawValue)
                                                    .font(.caption2)
                                            }
                                            .frame(width: 60, height: 50)
                                            .background(
                                                viewModel.selectedVideoFilter == preset
                                                    ? Color.red.opacity(0.8)
                                                    : Color.black.opacity(0.3)
                                            )
                                            .foregroundColor(.white)
                                            .cornerRadius(10)
                                        }
                                        .disabled(viewModel.isRecording)
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .padding(.bottom, 20)
                        }

                        // Recording duration indicator (video mode only)
                        if viewModel.captureMode == .video && (viewModel.isRecording || viewModel.pendingVideoURL != nil) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(viewModel.pendingVideoURL != nil ? Color.orange : Color.red)
                                    .frame(width: 10, height: 10)
                                Text(formatDuration(viewModel.recordingDuration))
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                if viewModel.pendingVideoURL != nil {
                                    Text("Ready to save")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.orange)
                                } else {
                                    Text("/ 0:30")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(20)
                            .padding(.bottom, 10)
                        }

                        // Capture/Record button
                        if viewModel.captureMode == .photo {
                            // Photo capture button
                            Button(action: {
                                guard let pin = appState.currentPin else { return }
                                Task {
                                    await viewModel.capturePhoto(pin: pin)
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
                        } else {
                            // Video record button
                            Button(action: {
                                guard let pin = appState.currentPin else { return }
                                Task {
                                    if viewModel.isRecording || viewModel.pendingVideoURL != nil {
                                        await viewModel.stopRecording(pin: pin)
                                    } else {
                                        await viewModel.startRecording()
                                    }
                                }
                            }) {
                                ZStack {
                                    // Outer ring
                                    Circle()
                                        .stroke(
                                            (viewModel.isRecording || viewModel.pendingVideoURL != nil) ? Color.red : Color.white,
                                            lineWidth: 4
                                        )
                                        .frame(width: 90, height: 90)

                                    // Inner shape
                                    if viewModel.isRecording {
                                        // Recording - show stop square
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.red)
                                            .frame(width: 35, height: 35)
                                    } else if viewModel.pendingVideoURL != nil {
                                        // Pending save - show checkmark
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 30, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 70, height: 70)
                                            .background(Color.orange)
                                            .clipShape(Circle())
                                    } else {
                                        // Idle - show red circle
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 70, height: 70)
                                    }
                                }
                            }
                            .scaleEffect(viewModel.isCapturing ? 0.9 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.isRecording)
                            .padding(.bottom, 40)
                            .disabled(viewModel.isCapturing)
                        }
                    }
                } else {
                    // Camera not ready - show message
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color(.secondarySystemBackground))
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
                        Text(viewModel.captureMode == .video ? "Encrypting video..." : "Encrypting photo...")
                            .foregroundColor(.white)
                            .padding(.top)
                    }
                }
            }
            .navigationTitle("Camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        selectedTab = 0 // Switch to Gallery
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .disabled(viewModel.isRecording)
                }
            }
            .onAppear {
                Task {
                    await viewModel.loadAlbums()
                    await viewModel.loadKeys()
                    await viewModel.checkPermissions()
                    await viewModel.startCamera()
                }
            }
            .onDisappear {
                viewModel.stopCamera()
            }
        }
    }

    /// Format duration for display
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
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
