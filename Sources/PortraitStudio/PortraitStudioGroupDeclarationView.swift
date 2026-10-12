import PortraitCore
import PortraitLibrary
import SwiftUI

struct PortraitStudioGroupDeclarationView: View {
  @Bindable var model: PortraitStudioReviewModel
  let drawing: SavedDrawing

  var body: some View {
    DisclosureGroup("Evaluation groups") {
      VStack(alignment: .leading, spacing: 8) {
        Text("Declare the person and photographic session using your own identifiers. Blank values stay unknown; capture UUIDs do not establish either group.")
          .font(.caption).foregroundStyle(.secondary)
        TextField("Subject identifier (optional)", text: $model.subjectID)
        TextField("Photographic session identifier (optional)", text: $model.photoSessionID)
        TextField("Declaration provenance", text: $model.groupProvenance)
        Picker("Fixed dataset split", selection: $model.groupSplit) {
          ForEach(PortraitReviewDatasetSplit.allCases, id: \.rawValue) { split in
            Text(split.rawValue.capitalized).tag(split)
          }
        }
        Text("Assigned splits require both human groups and provenance. Connected subject, session, source and ancestry groups must stay in one split. A declaration is immutable once saved.")
          .font(.caption).foregroundStyle(.secondary)
        if model.groupDeclaration != nil {
          Text("Declaration retained. Physical session independence and generalization remain unverified.")
            .font(.caption).foregroundStyle(.secondary)
        } else {
          Button("Save Group Declaration") { Task { await model.declareGroups() } }
            .disabled(!model.canDeclareGroups)
        }
      }
      .textFieldStyle(.roundedBorder)
      .disabled(model.groupDeclaration != nil || model.isLoading)
      .padding(.top, 6)
    }
    .task(id: drawing.id + (drawing.sourcePhotoID?.uuidString ?? drawing.transferOrigin?.identityHash.description ?? "")) {
      await model.loadGroups(for: drawing)
    }
  }
}
