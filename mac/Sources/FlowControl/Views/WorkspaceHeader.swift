import SwiftUI

struct WorkspaceHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) {
                heading
                Spacer(minLength: 16)
                actions()
            }

            VStack(alignment: .leading, spacing: 12) {
                heading
                actions()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension WorkspaceHeader where Actions == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}
