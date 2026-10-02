import SwiftUI
import TrackCore

/// The app after the first screen: the four tabs of the website, on the system tab bar (Liquid Glass on iOS 26).
struct MainView: View {
    @State private var settingsOpen = false

    var body: some View {
        TabView {
            HomeView(settingsOpen: $settingsOpen)
                .tabItem { Label("Home", systemImage: "house") }
            HistoryView(settingsOpen: $settingsOpen)
                .tabItem { Label("History", systemImage: "calendar") }
            ComingSoonPage(title: "Progress", detail: "Your volume chart and records arrive in the next build.", settingsOpen: $settingsOpen)
                .tabItem { Label("Progress", systemImage: "chart.bar") }
            ComingSoonPage(title: "Rank", detail: "Muscle ranks arrive in the next build.", settingsOpen: $settingsOpen)
                .tabItem { Label("Rank", systemImage: "medal") }
        }
        .tint(Palette.accent)
        .sheet(isPresented: $settingsOpen) { SettingsView() }
    }
}

/// A tab's page, as on the website: the brand and Settings on top, a muted line over a large title, then content.
struct Page<Content: View>: View {
    let caption: String?
    let title: String
    @Binding var settingsOpen: Bool
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Brand()
                    Spacer()
                    Button { settingsOpen = true } label: {
                        Image(systemName: "gearshape").font(.body.weight(.semibold)).foregroundStyle(Palette.text)
                            .frame(width: 44, height: 44).glass(radius: 22, fill: Palette.control, lifted: false)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Settings")
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let caption { Text(caption).font(.subheadline).foregroundStyle(Palette.muted) }
                    Text(title).font(.largeTitle.weight(.bold)).foregroundStyle(Palette.text)
                }
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Backdrop())
    }
}

/// A section heading with an optional count, as "Your splits 2".
struct SectionTitle: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Palette.text)
            if let count { Text("\(count)").font(.subheadline).foregroundStyle(Palette.muted) }
        }
    }
}

/// One row in a grouped glass list: a 44pt tile, a name over one line of detail, then the row's end.
struct ListRow<Trailing: View>: View {
    let icon: String
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(Palette.text)
                .frame(width: 44, height: 44).glass(radius: 12, fill: Palette.control, lifted: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Palette.text).lineLimit(1)
                Text(detail).font(.subheadline).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 12)
    }
}

/// Rows split by the Settings hairline, on one glass card.
struct GroupedList<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Rectangle().fill(Palette.hairline).frame(height: 1) }
                    row
                }
            }
        }
        .padding(.horizontal, 16)
        .glass()
    }
}

/// A calm empty state on a glass card.
struct EmptyCard: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(Palette.muted)
                .frame(width: 56, height: 56).glass(radius: 16, fill: Palette.control, lifted: false)
            Text(title).font(.headline).foregroundStyle(Palette.text)
            Text(detail).font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glass()
    }
}

private struct ComingSoonPage: View {
    let title: String
    let detail: String
    @Binding var settingsOpen: Bool

    var body: some View {
        Page(caption: nil, title: title, settingsOpen: $settingsOpen) {
            EmptyCard(icon: "hammer", title: "Coming soon", detail: detail)
        }
    }
}
