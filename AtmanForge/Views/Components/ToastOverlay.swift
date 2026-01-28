import SwiftUI

struct AppToast: Identifiable {
    let id = UUID()
    let message: String
    let icon: String
    let style: ToastStyle

    enum ToastStyle {
        case info, success, error
    }
}

struct ToastOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 8) {
            ForEach(appState.toasts) { toast in
                toastView(toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 12)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.25), value: appState.toasts.map(\.id))
    }

    private func toastView(_ toast: AppToast) -> some View {
        HStack(spacing: 6) {
            Image(systemName: toast.icon)
                .foregroundStyle(accentColor(for: toast.style))
            Text(toast.message)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(accentColor(for: toast.style).opacity(0.3), lineWidth: 0.5)
        )
        .frame(maxWidth: 300)
    }

    private func accentColor(for style: AppToast.ToastStyle) -> Color {
        switch style {
        case .info: return .primary
        case .success: return .green
        case .error: return .red
        }
    }
}
