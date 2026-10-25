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

/// Settings → Data's backup rows: export a backup (Files, AirDrop, anywhere the share sheet goes) or restore one, including
/// a backup from the website.
struct BackupSection: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var restored = 0

    var body: some View {
        // While the saved copy can't be read, the export is that file as it is (the website's recovery export), not
        // the empty app.
        if let unreadable = model.unreadableFile {
            ShareLink(item: unreadable) { Row(title: "Export unreadable data", value: "The copy Track couldn’t read") }
            .buttonStyle(RowPressStyle())
        } else {
            ShareLink(item: BackupFile(training: model.training),
                      preview: SharePreview("Track backup", image: Image(systemName: "doc"))) { Row(title: "Export backup", value: "JSON file") }
            .buttonStyle(RowPressStyle())
        }
        Button { importing = true } label: { Row(title: "Restore backup", value: "Replaces your data") }
        .buttonStyle(RowPressStyle())
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let backup = try? TrainingFile.decode(data), backup.isValid else {
                model.show("Not a Track backup file.")
                return
            }
            // Track's own dialog, with the website's wording.
            model.confirm = Confirm(title: "Restore this backup?",
                                    message: "It has \(count(backup.sessions.count, "workout")) and \(count(backup.splits.count, "split")), and replaces everything in Track now.",
                                    label: "Replace my data", destructive: true) {
                model.restore(backup)
                restored += 1
                model.show("Backup restored")
            }
        }
        .sensoryFeedback(.success, trigger: restored)
    }
}
