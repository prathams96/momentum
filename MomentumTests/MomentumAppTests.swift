import XCTest
import MomentumCore
import SwiftData
@testable import Momentum

@MainActor
final class MomentumAppTests: XCTestCase {
    func testPreviewContainerUsesTheV1Schema() throws {
        let container = try ModelContainerFactory.makePreview()

        XCTAssertNotNil(container)
    }

    func testSeedDataIsIdempotentAndContainsCanonicalRoutines() throws {
        let container = try ModelContainerFactory.makePreview()
        try SeedData.install(
            in: container.mainContext,
            currentDomainDay: DomainDay(year: 2026, month: 8, day: 2)
        )
        try SeedData.install(
            in: container.mainContext,
            currentDomainDay: DomainDay(year: 2026, month: 8, day: 3)
        )

        let workouts = try container.mainContext.fetch(FetchDescriptor<WorkoutTemplateRecord>())
        let routines = try container.mainContext.fetch(FetchDescriptor<CareRoutineTemplateRecord>())
        let settings = try container.mainContext.fetch(FetchDescriptor<AppSettingsRecord>())

        XCTAssertEqual(workouts.count, 4)
        XCTAssertEqual(routines.count, 5)
        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(settings.first?.seedVersion, SeedData.currentVersion)
        XCTAssertTrue(routines.allSatisfy { routine in
            !routine.name.localizedCaseInsensitiveContains("pilgrim") &&
            !routine.name.localizedCaseInsensitiveContains("conscious chemist")
        })
    }
}
