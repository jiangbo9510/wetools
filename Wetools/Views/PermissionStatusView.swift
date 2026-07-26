import SwiftUI

struct PermissionStatusView: View {
    let title: String
    let isGranted: Bool
    let grantedText: String
    let requiredText: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isGranted ? .green : .orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(isGranted ? grantedText : requiredText)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            Spacer()

            Button(actionTitle, action: action)
                .disabled(isGranted)
        }
        .padding(.vertical, 6)
    }
}
