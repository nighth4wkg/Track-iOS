import CoreTransferable
import SwiftUI
import TrackCore
import UniformTypeIdentifiers

/// The training data as a backup file: the same JSON the website exports and restores ("track-backup-<day>.json").
struct BackupFile: Transferable {
    let training: Training

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { backup in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("track-backup-\(dayKey(nowMillis())).json")
            try TrainingFile.encode(backup.training).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// Settings → Your data: export a backup (Files, AirDrop, anywhere the share sheet goes) or restore one, including
/// a backup from the website.
struct BackupSection: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var pending: Training?
    @State private var restored = 0

    var body: some View {
        ShareLink(item: BackupFile(training: model.training),
                  preview: SharePreview("Track backup", image: Image(systemName: "doc"))) {
            ListRow(icon: "square.and.arrow.up", title: "Export backup", detail: "Save a copy of everything as a file") { EmptyView() }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        Button { importing = true } label: {
            ListRow(icon: "square.and.arrow.down", title: "Restore backup", detail: "Replace this iPhone’s data from a file") { EmptyView() }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let backup = try? TrainingFile.decode(data), backup.version == 1 else {
                model.message = "This file is not a valid Track backup."
                return
            }
            pending = backup
        }
        .confirmationDialog("Replace this iPhone’s data?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button("Restore backup", role: .destructive) {
                if let pending { model.restore(pending); restored += 1 }
                pending = nil
            }
        } message: {
            if let pending {
                Text("The backup has \(count(pending.sessions.count, "workout")) and \(count(pending.splits.count, "split")). What’s on this iPhone now is replaced.")
            }
        }
        .sensoryFeedback(.success, trigger: restored)
    }
}
