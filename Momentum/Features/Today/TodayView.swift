import MomentumCore
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettingsRecord]

    @State private var reconciliationError: String?

    private let calendar = Calendar.autoupdatingCurrent
    @Binding private var notificationWorkoutRoute: WorkoutNotificationRoute?

    init(notificationWorkoutRoute: Binding<WorkoutNotificationRoute?> = .constant(nil)) {
        _notificationWorkoutRoute = notificationWorkoutRoute
    }

    private var canonicalSettings: AppSettingsRecord? {
        AppSettingsRecord.canonical(in: settings)
    }

    private var currentDomainDay: DomainDay {
        ScheduleProjection.currentDomainDay(settings: settings, now: .now, calendar: calendar)
    }

    var body: some View {
        let context = ModuleContext.make(in: modelContext, settings: canonicalSettings)
        let contributors = ModuleRegistry.standard
            .enabledModules(ModuleEnablementStore.enabledIDs(from: canonicalSettings))
            .compactMap { $0 as? any TodayContributing }
        let contributions = contributors.compactMap { $0.todayContribution(in: context) }
        let sections = contributors.compactMap { $0.todaySection(in: context) }

        ScrollView {
            VStack(alignment: .leading, spacing: MomentumSpacing.xl) {
                dateLine(contributions)
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    section
                }
                consistencySection
            }
            .padding(.horizontal, MomentumSpacing.md)
            .padding(.top, MomentumSpacing.xs)
            .padding(.bottom, 96)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .environment(\.notificationWorkoutRoute, $notificationWorkoutRoute)
        .task(id: PersistedDomainDay.encode(currentDomainDay)) {
            do {
                try await DailyReconciler.reconcileAndNotify(in: modelContext)
            } catch {
                reconciliationError = "Today’s reminders could not be refreshed. Try again in a moment."
            }
        }
        .alert("Couldn’t refresh today", isPresented: Binding(
            get: { reconciliationError != nil },
            set: { if !$0 { reconciliationError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reconciliationError ?? "Try again in a moment.")
        }
    }

    // MARK: - Daily thread

    private func dateLine(_ contributions: [TodayContribution]) -> some View {
        let stages = dailyThreadStages(from: contributions)
        return DailyThreadHeader(
            date: PersistedDomainDay.date(for: currentDomainDay, calendar: calendar)?.formatted(date: .complete, time: .omitted) ?? "Today",
            accessibilityDate: PersistedDomainDay.date(for: currentDomainDay, calendar: calendar)?.formatted(date: .abbreviated, time: .omitted) ?? "Today",
            stages: stages,
            callout: dailyThreadCallout(contributions: contributions, stages: stages)
        )
    }

    private func dailyThreadStages(from contributions: [TodayContribution]) -> [DailyThreadStageModel] {
        var stages = contributions.map { contribution in
            DailyThreadStageModel(
                title: contribution.title,
                symbol: contribution.symbolName,
                tint: contribution.tint,
                isFocused: false
            )
        }
        stages.append(DailyThreadStageModel(title: "Reflect", symbol: "chart.xyaxis.line", tint: nil, isFocused: false))

        if let focusIndex = contributions.firstIndex(where: { $0.state != .completed }) {
            stages[focusIndex].isFocused = true
        } else {
            stages[stages.count - 1].isFocused = true
        }
        return stages
    }

    private func dailyThreadCallout(contributions: [TodayContribution], stages: [DailyThreadStageModel]) -> String {
        if let attention = contributions.first(where: { $0.state == .attention }) {
            return attention.title == "Workout" ? "Repair workout plan" : "\(attention.title) needs attention"
        }
        if let focused = stages.first(where: \.isFocused) {
            return "\(focused.title) next"
        }
        return "Reflect next"
    }

    // MARK: - Consistency

    private var consistencySection: some View {
        TodayConsistencySection(currentDay: currentDomainDay, calendar: calendar)
    }
}

// MARK: - Daily thread visuals

struct DailyThreadStageModel: Identifiable {
    let title: String
    let symbol: String
    let tint: Color?
    var isFocused: Bool

    var id: String { title }
}

private struct DailyThreadHeader: View {
    let date: String
    let accessibilityDate: String
    let stages: [DailyThreadStageModel]
    let callout: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var threadNodeSize = 28
    @State private var isRevealed = false

    private var focusedTitle: String {
        stages.first(where: \.isFocused)?.title ?? "Reflect"
    }

    private var stageSummary: String {
        let titles = stages.map(\.title)
        guard let last = titles.last else { return "" }
        let leading = titles.dropLast().joined(separator: ", ")
        return leading.isEmpty ? "\(last)." : "\(leading), then \(last)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.md) {
            VStack(alignment: .leading, spacing: MomentumSpacing.xxs) {
                Text(dynamicTypeSize.isAccessibilitySize ? accessibilityDate : date)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
                        promise
                        focusLabel
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: MomentumSpacing.sm) {
                        promise

                        Spacer(minLength: 0)

                        focusLabel
                    }
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                accessibilityThread
            } else {
                standardThread
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily thread")
        .accessibilityValue("\(accessibilityDate). One promise. Every day. \(callout). \(stageSummary)")
        .onAppear {
            guard !isRevealed else { return }
            if reduceMotion {
                isRevealed = true
            } else {
                withAnimation(.easeOut(duration: 0.48)) {
                    isRevealed = true
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: focusedTitle)
    }

    private var focusedNodeSize: CGFloat {
        threadNodeSize + 4
    }

    private var standardThread: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.secondary.opacity(0.20))
                    .frame(width: max(proxy.size.width - 52, 0), height: 2)
                    .offset(x: 26, y: focusedNodeSize / 2)
                    .scaleEffect(x: isRevealed ? 1 : 0.02, anchor: .leading)
            }

            HStack(alignment: .top, spacing: 0) {
                ForEach(stages) { stage in
                    DailyThreadStageView(
                        stage: stage,
                        isRevealed: isRevealed,
                        nodeSize: threadNodeSize
                    )
                }
            }
        }
        .frame(height: max(focusedNodeSize + 24, 56))
    }

    private var accessibilityThread: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: MomentumSpacing.md
        ) {
            ForEach(stages) { stage in
                DailyThreadStageView(
                    stage: stage,
                    isRevealed: isRevealed,
                    nodeSize: min(threadNodeSize, 52)
                )
            }
        }
        .background {
            GeometryReader { proxy in
                Path { path in
                    let top = min(threadNodeSize, 52) / 2
                    let bottom = proxy.size.height - top - 34
                    path.move(to: CGPoint(x: proxy.size.width * 0.25, y: top))
                    path.addLine(to: CGPoint(x: proxy.size.width * 0.75, y: top))
                    path.addCurve(
                        to: CGPoint(x: proxy.size.width * 0.25, y: bottom),
                        control1: CGPoint(x: proxy.size.width * 0.88, y: proxy.size.height * 0.45),
                        control2: CGPoint(x: proxy.size.width * 0.12, y: proxy.size.height * 0.55)
                    )
                    path.addLine(to: CGPoint(x: proxy.size.width * 0.75, y: bottom))
                }
                .trim(from: 0, to: isRevealed ? 1 : 0.02)
                .stroke(Color.secondary.opacity(0.20), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }

    private var promise: some View {
        Text("One promise. Every day.")
            .font(.title2.bold())
            .fixedSize(horizontal: false, vertical: true)
    }

    private var focusLabel: some View {
        Label(callout, systemImage: "arrow.right")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MomentumTheme.pulse)
            .labelStyle(.titleAndIcon)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct DailyThreadStageView: View {
    let stage: DailyThreadStageModel
    let isRevealed: Bool
    let nodeSize: CGFloat

    private var tint: Color {
        stage.tint ?? (stage.isFocused ? MomentumTheme.pulse : Color.secondary)
    }

    var body: some View {
        VStack(spacing: MomentumSpacing.xxs) {
            ZStack {
                Circle()
                    .fill(stage.isFocused ? tint : Color(uiColor: .secondarySystemBackground))
                    .frame(
                        width: stage.isFocused ? nodeSize + 4 : nodeSize,
                        height: stage.isFocused ? nodeSize + 4 : nodeSize
                    )

                Image(systemName: stage.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stage.isFocused ? Color.white : Color.secondary)
            }
            .scaleEffect(stage.isFocused && !isRevealed ? 0.78 : 1)

            Text(stage.title)
                .font(.caption.weight(stage.isFocused ? .semibold : .regular))
                .foregroundStyle(stage.isFocused ? tint : Color.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Consistency

private struct TodayConsistencySection: View {
    @Query private var sessions: [WorkoutSessionRecord]
    @Query private var workoutEvents: [WorkoutDayEventRecord]
    @Query private var nutritionDays: [NutritionDayRecord]
    @Query private var careOccurrences: [CareOccurrenceRecord]

    let currentDay: DomainDay
    let calendar: Calendar

    private var adherenceFacts: [HistoryAdherenceFact] {
        let interval = MomentumDiagnostics.signposter.beginInterval("TodayAggregation")
        defer {
            MomentumDiagnostics.signposter.endInterval("TodayAggregation", interval)
        }
        return HistoryProjection.facts(
            sessions: sessions,
            workoutEvents: workoutEvents,
            nutritionDays: nutritionDays,
            careOccurrences: careOccurrences
        )
    }

    private var adherenceStreaks: HistoryStreakSummary {
        HistoryProjection.streaks(facts: adherenceFacts, calendar: calendar)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Consistency")
                    .font(.title3.bold())
                Spacer()
                Text("Last 16 weeks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            CompactHistoryHeatmapView(currentDay: currentDay, calendar: calendar) { day in
                HistoryProjection.adherenceScore(on: day, facts: adherenceFacts, category: .all)
            }

            HistoryStreakSummaryView(summary: adherenceStreaks, category: .all)
        }
    }
}
