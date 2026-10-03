import SwiftUI
import TrackCore

/// One month of training at a glance, as the website's calendar: the month over its workouts · time, ‹ › through the
/// months that have workouts up to this one, and a Monday-first grid. Trained days are lit (today's in the accent),
/// today is ringed. Tapping a trained day shows only it; tapping it again, all.
struct HistoryCalendar: View {
    @Binding var month: Date
    @Binding var day: String?
    let sessions: [Session]

    var body: some View {
        let calendar = Calendars.local
        let inMonth = sessions.filter { calendar.isDate(Date(timeIntervalSince1970: Double($0.finishedAt!) / 1000), equalTo: month, toGranularity: .month) }
        let trained = Set(sessions.map { dayKey($0.finishedAt!) })
        let days = calendar.range(of: .day, in: .month, for: month)!.count
        let lead = (calendar.component(.weekday, from: month) + 5) % 7
        let today = dayKey(nowMillis())
        let isCurrent = calendar.isDate(month, equalTo: .now, toGranularity: .month)
        let earliest = sessions.compactMap(\.finishedAt).min().map { Self.monthStart(Date(timeIntervalSince1970: Double($0) / 1000)) } ?? month
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(month.formatted(.dateTime.month(.wide).year(calendar.isDate(month, equalTo: .now, toGranularity: .year) ? .omitted : .defaultDigits)))
                        .font(.headline).foregroundStyle(Palette.text)
                    Text(inMonth.isEmpty ? "No workouts" : "\(count(inMonth.count, "workout")) · \(trainingDuration(inMonth.reduce(0) { $0 + $1.minutes }))")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }
                Spacer()
                GlassCircleButton(icon: "chevron.left", label: "Previous month") { step(-1) }
                    .disabled(month <= earliest).opacity(month <= earliest ? 0.4 : 1)
                GlassCircleButton(icon: "chevron.right", label: "Next month") { step(1) }.disabled(isCurrent).opacity(isCurrent ? 0.4 : 1)
            }
            HStack(spacing: 6) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, letter in
                    Text(letter).font(.caption.weight(.bold)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(-lead..<0, id: \.self) { _ in Color.clear.frame(height: 36) }
                ForEach(1...days, id: \.self) { number in
                    let date = calendar.date(byAdding: .day, value: number - 1, to: month)!
                    let key = dayKey(millis(date))
                    let lit = trained.contains(key)
                    let isToday = key == today
                    Button { if lit { withAnimation(.smooth) { day = day == key ? nil : key } } } label: {
                        Text("\(number)").font(.subheadline.weight(lit ? .bold : .regular)).monospacedDigit()
                            .foregroundStyle(isToday && lit ? Palette.primaryText : lit ? Palette.text : key > today ? Palette.muted.opacity(0.35) : Palette.muted.opacity(0.7))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isToday && lit ? Palette.primary : lit ? Palette.control : Palette.input.opacity(0.5)))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(day == key ? Palette.text : isToday && !lit ? Palette.accent : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .disabled(!lit)
                    .accessibilityLabel(date.formatted(.dateTime.month(.wide).day()) + (lit ? ", trained" : ""))
                }
            }
            .id(month)
            .transition(.opacity)
        }
        .padding(16)
        .glass()
        .onAppear {
            // Opens on this month, or on the latest workout's month when this one has none yet.
            if inMonth.isEmpty, let latest = sessions.compactMap(\.finishedAt).max() {
                month = Self.monthStart(Date(timeIntervalSince1970: Double(latest) / 1000))
            }
        }
    }

    static func monthStart(_ date: Date) -> Date { Calendars.local.dateInterval(of: .month, for: date)!.start }

    private func step(_ months: Int) {
        withAnimation(.smooth(duration: 0.25)) {
            month = Calendars.local.date(byAdding: .month, value: months, to: month)!
            day = nil
        }
    }
}
