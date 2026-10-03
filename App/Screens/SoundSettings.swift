import SwiftUI

/// Choosing Track's sounds: each moment with the sound it plays; tap one to hear the whole list and pick by ear.
struct SoundSettings: View {
    @Environment(\.dismiss) private var dismiss
    @State private var version = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("These are iPhone’s own sounds. Tap a moment, then tap any sound to hear it.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    GlassList {
                        ForEach(Sound.allCases) { sound in
                            NavigationLink { SoundList(sound: sound) { version += 1 } } label: {
                                HStack {
                                    Text(sound.title).foregroundStyle(Palette.text)
                                    Spacer()
                                    Text(Sounds.choice(sound).map(Sounds.name) ?? "None").font(.subheadline).foregroundStyle(Palette.muted).lineLimit(1)
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                                }
                                .frame(minHeight: 36).contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    .id(version)
                }
                .padding(16)
            }
            .background(Backdrop())
            .navigationTitle("Sounds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Palette.text) }.accessibilityLabel("Close")
                }
            }
        }
    }
}

/// Every sound on the iPhone for one moment: tap to hear it and choose it.
private struct SoundList: View {
    let sound: Sound
    let changed: () -> Void
    @State private var chosen: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                row(nil)
                ForEach(Sounds.all, id: \.self) { row($0) }
            }
            .glass()
            .padding(16)
        }
        .background(Backdrop())
        .navigationTitle(sound.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { chosen = Sounds.choice(sound) }
        .sensoryFeedback(.selection, trigger: chosen)
    }

    private func row(_ file: String?) -> some View {
        Button {
            chosen = file
            Sounds.choose(file, for: sound)
            if let file { Sounds.preview(file) }
            changed()
        } label: {
            HStack {
                Text(file.map(Sounds.name) ?? "None").foregroundStyle(Palette.text).lineLimit(1)
                Spacer()
                if chosen == file { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Palette.accent) }
            }
            .padding(.horizontal, 16).frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}
