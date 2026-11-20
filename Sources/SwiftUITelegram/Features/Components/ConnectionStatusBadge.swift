import SwiftUI

struct ConnectionStatusBadge: View {
    let status: ConnectionStatus

    var body: some View {
        if let text = status.displayText {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
        }
    }
}
