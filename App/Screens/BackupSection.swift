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
    @State private var restored = 0

    var body: some View {
        // While the saved copy can't be read, the export is that file as it is (the website's recovery export), not
        // the empty app.
        if let unreadable = model.unreadableFile {
            ShareLink(item: unreadable) {
                ListRow(icon: "square.and.arrow.up", title: "Export unreadable data", detail: "Save the copy Track couldn’t read") { EmptyView() }
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        } else {
            ShareLink(item: BackupFile(training: model.training),
                      preview: SharePreview("Track backup", image: Image(systemName: "doc"))) {
                ListRow(icon: "square.and.arrow.up", title: "Export backup", detail: "Save a copy of everything as a file") { EmptyView() }
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
        Button { importing = true } label: {
            ListRow(icon: "square.and.arrow.down", title: "Restore backup", detail: "Replace this iPhone’s data from a file") { EmptyView() }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let backup = try? TrainingFile.decode(data), backup.isValid else {
                model.show("This file is not a valid Track backup.")
                return
            }
            // Track's own dialog, with the website's wording.
            model.confirm = Confirm(title: "Restore this backup?",
                                    message: "Replace current data with \(count(backup.splits.count, "split")) and \(count(backup.sessions.count, "session")). Export your current data first if you want to keep it.",
                                    label: "Restore backup", destructive: true) {
                model.restore(backup)
                restored += 1
                model.show("Backup restored")
            }
        }
        .sensoryFeedback(.success, trigger: restored)
    }
}
