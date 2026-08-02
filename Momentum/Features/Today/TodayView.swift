import Foundation
import MomentumCore
import SwiftData
import SwiftUI

struct TodayView: View {
    @Query private var settings: [AppSettingsRecord]
    @Query private var anchors: [CycleAnchorRecord]
    @Query(sort: \WorkoutTemplateRecord.sequenceIndex) private var workouts: [WorkoutTemplateRecord]
    @Query private var exercises: [ExercisePrescriptionRecord]
    @Query(sort: \CareRoutineTemplateRecord.notificationMinutes) private var routines: [CareRoutineTemplateRecord]

    private var anchor: CycleAnchorRecord? { anchors.first }

    private var nextWorkout: WorkoutTemplateRecord? {
        guard let anchor else { return workouts.first }
        return workouts.first { $0.id == anchor.nextWorkoutTemplateID } ?? workouts.first
    }

    private var today: DomainDay {
        DomainDay.containing(
            .now,
            calendar: .autoupdatingCurrent,
            cutoffMinutes: settings.first?.domainDayCutoffMinutes ?? 180
        )
    }

    private var dueDay: DomainDay? {
        guard let value = anchor?.firstDueDomainDay else { return nil }
        return parse(value)
    }

    private var dueLabel: String {
        guard let dueDay else { return "Ready when you are" }
        if dueDay == today { return "Due today" }
        if dueDay < today { return "Due since \(formatted(dueDay))" }
        return "Due \(formatted(dueDay))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MomentumSpacing.xxl) {
                dateLine

                if let nextWorkout {
                    workoutSection(nextWorkout)
                } else {
                    emptyWorkoutSection
                }

                activitySection
                consistencySection
            }
            .padding(.horizontal, MomentumSpacing.md)
            .padding(.top, MomentumSpacing.xs)
            .padding(.bottom, MomentumSpacing.xl)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
    }

    private var dateLine: some View {
        Text(Date.now.formatted(date: .complete, time: .omitted))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func workoutSection(_ workout: WorkoutTemplateRecord) -> some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.md) {
            Text("Next")
                .font(.title3.bold())

            NavigationLink {
                WorkoutPlanView(
                    workout: workout,
                    exercises: exercises.filter { $0.workoutTemplateID == workout.id }
                )
            } label: {
                VStack(alignment: .leading, spacing: MomentumSpacing.md) {
                    HStack(alignment: .top, spacing: MomentumSpacing.md) {
                        VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
                            Text(dueLabel)
                                .font(.headline)
                                .foregroundStyle(MomentumTheme.pulse)

                            Text(workout.name)
                                .font(.largeTitle.bold())
                                .foregroundStyle(.primary)
                                .minimumScaleFactor(0.85)

                            ThreadUnderline()
                                .stroke(MomentumTheme.pulse, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 112, height: 12)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.title2)
                            .foregroundStyle(MomentumTheme.pulse)
                            .frame(width: 48, height: 48)
                            .background(Color(uiColor: .systemBackground).opacity(0.70))
                            .clipShape(Circle())
                    }

                    Text(workout.focus)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Label("\(exerciseCount(for: workout)) exercises", systemImage: "list.number")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Label("Start Workout", systemImage: "arrow.up.right")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .padding(.vertical, MomentumSpacing.sm)
                    .padding(.horizontal, MomentumSpacing.md)
                    .background(MomentumTheme.pulse)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(MomentumSpacing.md)
                .background(MomentumTheme.pulseWash)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the \(workout.name) workout plan")
        }
    }

    private var emptyWorkoutSection: some View {
        ContentUnavailableView(
            "Your next workout is not set",
            systemImage: "figure.strengthtraining.traditional",
            description: Text("Open Plans to choose the next workout in your cycle.")
        )
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.md) {
            Text("Keep the day moving")
                .font(.title3.bold())

            VStack(spacing: 0) {
                ActivityRow(
                    symbol: "fork.knife",
                    title: "Nutrition",
                    detail: "Log food when you eat",
                    tint: MomentumTheme.dataCyan
                )
                Divider().padding(.leading, 52)
                ActivityRow(
                    symbol: "sun.max",
                    title: "Morning care",
                    detail: "Due at \(timeText(for: routines.first))",
                    tint: MomentumTheme.pulse
                )
                Divider().padding(.leading, 52)
                ActivityRow(
                    symbol: "moon",
                    title: "Night care",
                    detail: "Due at \(timeText(for: routines.dropFirst(1).first))",
                    tint: MomentumTheme.pulseDeep
                )
            }
        }
    }

    private var consistencySection: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Consistency")
                    .font(.title3.bold())

                Spacer()

                Text("Last 16 weeks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 5) {
                ForEach(0..<16, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.14))
                        .frame(height: 18)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Consistency history")
            .accessibilityValue("No completed days yet")

            Text("Your first completed day will appear here.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func exerciseCount(for workout: WorkoutTemplateRecord) -> Int {
        exercises.filter { $0.workoutTemplateID == workout.id }.count
    }

    private func timeText(for routine: CareRoutineTemplateRecord?) -> String {
        guard let routine else { return "scheduled time" }
        let hour = routine.notificationMinutes / 60
        let minute = routine.notificationMinutes % 60
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.autoupdatingCurrent.date(from: components) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func parse(_ value: String) -> DomainDay? {
        let pieces = value.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        return DomainDay(year: pieces[0], month: pieces[1], day: pieces[2])
    }

    private func formatted(_ day: DomainDay) -> String {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        let date = Calendar.autoupdatingCurrent.date(from: components) ?? .now
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct ActivityRow: View {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: MomentumSpacing.md) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, MomentumSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}

private struct WorkoutPlanView: View {
    let workout: WorkoutTemplateRecord
    let exercises: [ExercisePrescriptionRecord]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
                    Text(workout.focus)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Label("\(exercises.count) exercises", systemImage: "list.number")
                        .font(.subheadline.weight(.medium))
                }
                .padding(.vertical, MomentumSpacing.xs)
            }

            Section("Exercises") {
                ForEach(exercises.sorted { $0.orderIndex < $1.orderIndex }) { exercise in
                    HStack(alignment: .top, spacing: MomentumSpacing.md) {
                        Text("\(exercise.orderIndex + 1)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(MomentumTheme.pulse)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(exercise.displayName)
                                .font(.headline)
                            Text("\(exercise.workingSetCount) sets · \(exercise.repMinimum)–\(exercise.repMaximum) reps")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, MomentumSpacing.xs)
                }
            }

            Section {
                Text("Session tracking is the next step. This plan is ready when you are.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MomentumThreadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.midY),
            control1: CGPoint(x: rect.width * 0.20, y: rect.minY),
            control2: CGPoint(x: rect.width * 0.30, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.width * 0.70, y: rect.minY),
            control2: CGPoint(x: rect.width * 0.80, y: rect.maxY)
        )
        return path
    }
}

private struct ThreadUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.width * 0.30, y: rect.minY),
            control2: CGPoint(x: rect.width * 0.70, y: rect.maxY)
        )
        return path
    }
}
