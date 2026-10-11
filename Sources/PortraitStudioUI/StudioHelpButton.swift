import SwiftUI

/// Explanations stay available without occupying the editing canvas.
package struct StudioHelpButton: View {
  package let title: String
  package let text: String
  @State private var isPresented = false

  package init(_ title: String, text: String) {
    self.title = title
    self.text = text
  }

  package var body: some View {
    Button { isPresented.toggle() } label: {
      Image(systemName: "questionmark.circle")
        .foregroundStyle(.secondary)
        .frame(width: 20, height: 20)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("About \(title)")
    .help(title)
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.headline)
        ViewThatFits(in: .vertical) {
          Text(text).font(.callout).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
          ScrollView {
            Text(text).font(.callout).textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .frame(maxHeight: 480)
      }
      .padding(16)
      .frame(width: 320, alignment: .leading)
    }
  }
}
