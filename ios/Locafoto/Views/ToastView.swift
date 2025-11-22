import SwiftUI

// MARK: - Toast Type
enum ToastType {
    case success
    case error

    var backgroundColor: Color {
        switch self {
        case .success:
            return Color.green.opacity(0.85)
        case .error:
            return Color.red.opacity(0.85)
        }
    }

    var icon: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "xmark.circle.fill"
        }
    }
}

// MARK: - Toast Data
struct ToastData: Equatable {
    let type: ToastType
    let message: String
    let id: UUID = UUID()

    static func == (lhs: ToastData, rhs: ToastData) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Toast Manager
@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var currentToast: ToastData?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ message: String, type: ToastType) {
        dismissTask?.cancel()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentToast = ToastData(type: type, message: message)
        }

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.currentToast = nil
                    }
                }
            }
        }
    }

    func showSuccess(_ message: String) {
        show(message, type: .success)
    }

    func showError(_ message: String) {
        show(message, type: .error)
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.3)) {
            currentToast = nil
        }
    }
}

// MARK: - Toast View
struct ToastView: View {
    let toast: ToastData

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.type.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)

            Text(toast.message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(3)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(toast.type.backgroundColor)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Toast Container Modifier
struct ToastContainerModifier: ViewModifier {
    @ObservedObject var toastManager = ToastManager.shared

    func body(content: Content) -> some View {
        ZStack {
            content

            VStack {
                if let toast = toastManager.currentToast {
                    ToastView(toast: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture {
                            toastManager.dismiss()
                        }
                }
                Spacer()
            }
            .padding(.top, 50)
        }
    }
}

// MARK: - View Extension
extension View {
    func withToastContainer() -> some View {
        modifier(ToastContainerModifier())
    }
}

// MARK: - Preview
#Preview {
    VStack {
        Button("Show Success") {
            ToastManager.shared.showSuccess("Photo saved successfully!")
        }
        Button("Show Error") {
            ToastManager.shared.showError("Failed to import photos")
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .withToastContainer()
}
