import Charts
import SwiftUI

struct FocusPage: View {
  @EnvironmentObject private var store: WorkspaceStore
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 8) {
          Eyebrow(wording: .focusEyebrow)
          EditableWording(.focusTitle).font(.strukturSerif(35)).tracking(-1)
          EditableWording(.focusSubtitle)
            .font(.system(size: 12)).foregroundStyle(StrukturTheme.muted)
        }.padding(30)
        Divider()
        HStack(alignment: .top, spacing: 22) {
          VStack(alignment: .leading, spacing: 18) {
            FocusWidget(expanded: true).frame(minHeight: 390)
              .background(StrukturTheme.lavender, in: RoundedRectangle(cornerRadius: 20))
            let records = (store.workspace.focusHistory ?? []).filter {
              Calendar.struktur.isDateInToday($0.endedAt)
            }
            HStack(spacing: 14) {
              ProjectMetric(
                title: "Focused today", value: durationText(records.reduce(0) { $0 + $1.seconds }),
                detail: "recorded focus time", color: .lilac)
              ProjectMetric(
                title: "Sessions", value: "\(records.count)", detail: "saved to your workspace",
                color: .mint)
            }
            if let record = records.last, record.completed {
              Label(
                "Session complete.",
                systemImage: "checkmark.circle"
              )
              .font(.caption).foregroundStyle(StrukturTheme.muted)
            }
            Spacer()
          }.frame(maxWidth: .infinity)
          ScratchpadView().frame(width: 330).frame(minHeight: 500).strukturCard(padding: 0)
        }.padding(30)
      }
    }.scrollIndicators(.hidden)
  }
}

struct ScratchpadView: View {
  @EnvironmentObject private var store: WorkspaceStore
  @State private var preview = false
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Label("Focus notes", systemImage: "note.text").font(.strukturSerif(20, weight: .semibold))
        Spacer()
      }
      MarkdownComposer(
        text: Binding(get: { store.scratchpad }, set: { store.updateScratchpad($0) }),
        showingPreview: $preview)
      Spacer()
      Text("Saved automatically to your workspace.").font(.caption2).foregroundStyle(.tertiary)
    }
    .padding(22)
    .onDisappear { store.saveNow() }
  }
}

struct InsightsPage: View {
  @EnvironmentObject private var store: WorkspaceStore

  private var weeklyData: [DayMetric] {
    (0..<7).map { offset in
      let day = store.weekStart(for: Date()).adding(days: offset)
      let completed = store.tasks.filter { task in
        task.completedAt.map { Calendar.struktur.isDate($0, inSameDayAs: day) } ?? false
      }.count
      let planned = store.scheduledSeconds(on: day) / 3600
      return DayMetric(day: day, completed: completed, scheduledHours: planned)
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 4) {
          EditableWording(.insightsTitle).font(.strukturSerif(30, weight: .semibold))
          EditableWording(.insightsSubtitle).font(.caption)
            .foregroundStyle(.secondary)
        }
        HStack(spacing: 14) {
          ProjectMetric(
            title: "Finished", value: "\(store.tasks.filter(\.isCompleted).count)",
            detail: "tasks in total", color: .mint)
          ProjectMetric(
            title: "Scheduled", value: scheduledLabel, detail: "hours this week", color: .lilac)
          ProjectMetric(
            title: "Open", value: "\(store.tasks.filter { !$0.isCompleted }.count)",
            detail: "across all spaces", color: .peach)
        }
        HStack(alignment: .top, spacing: 14) {
          VStack(alignment: .leading, spacing: 14) {
            Text("Scheduled hours").font(.strukturSerif(20, weight: .semibold))
            Chart(weeklyData) { item in
              BarMark(
                x: .value("Day", item.day, unit: .day), y: .value("Hours", item.scheduledHours)
              )
              .foregroundStyle(AccentToken.lilac.color.gradient)
              .cornerRadius(5)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 250)
          }.strukturCard().frame(maxWidth: .infinity)
          VStack(alignment: .leading, spacing: 14) {
            Text("Completed tasks").font(.strukturSerif(20, weight: .semibold))
            Chart(weeklyData) { item in
              LineMark(x: .value("Day", item.day, unit: .day), y: .value("Tasks", item.completed))
                // Piecewise monotone cubic interpolation stays between adjacent counts,
                // including flat zero runs, without the overshoot of Catmull–Rom.
                .foregroundStyle(AccentToken.mint.color).interpolationMethod(.monotone)
              PointMark(x: .value("Day", item.day, unit: .day), y: .value("Tasks", item.completed))
                .foregroundStyle(AccentToken.mint.color)
            }
            .chartYScale(domain: 0...max(4, weeklyData.map(\.completed).max() ?? 0))
            .frame(height: 250)
          }.strukturCard().frame(maxWidth: .infinity)
        }
        EditableWording(.insightsFooter)
          .font(.strukturSerif(18)).foregroundStyle(.secondary).padding(.vertical, 12)
      }.padding(28)
    }
  }

  private var scheduledLabel: String {
    String(format: "%.1f", weeklyData.reduce(0) { $0 + $1.scheduledHours })
  }
}

struct DayMetric: Identifiable {
  var id: Date { day }
  let day: Date
  let completed: Int
  let scheduledHours: Double
}
