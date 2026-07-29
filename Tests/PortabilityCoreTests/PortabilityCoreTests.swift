import XCTest
@testable import PortabilityCore

final class PortabilityCoreTests: XCTestCase {

    private let analyzer = PortabilityAnalyzer()

    // MARK: - Catalog integrity

    func testCatalogIdsAreUnique() {
        let ids = TransportCapability.catalog.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Capability slugs must be unique")
    }

    func testCatalogLookupReturnsNilForUnknownSlug() {
        XCTAssertNil(TransportCapability.catalogEntry(id: "not-a-capability"))
        XCTAssertEqual(TransportCapability.catalogEntry(id: "url-cache"), .urlCache)
    }

    func testWeightOrderingHoldsAcrossClasses() {
        XCTAssertLessThan(
            PortabilityClass.currencyType.migrationWeight,
            PortabilityClass.protocolLayer.migrationWeight
        )
        XCTAssertLessThan(
            PortabilityClass.protocolLayer.migrationWeight,
            PortabilityClass.platformService.migrationWeight
        )
    }

    // MARK: - Edge cases

    func testEmptyInventoryIsCheapAndCostsNothing() {
        let report = analyzer.analyze(declaredSeams: 1, usages: [])
        XCTAssertEqual(report.effectiveSurface, 0)
        XCTAssertEqual(report.migrationCost, 0, accuracy: 0.0001)
        XCTAssertEqual(report.verdict, .cheap(cost: 0))
        XCTAssertEqual(report.bypassSiteCount, 0)
    }

    /// The interesting divide-by-zero: a team with no declared abstraction at all.
    func testZeroDeclaredSeamsYieldsNilRatioNotACrash() {
        let report = analyzer.analyze(declaredSeams: 0, usages: SampleInventory.usages)
        XCTAssertNil(report.surfaceRatio)
        XCTAssertGreaterThan(report.effectiveSurface, 0)
    }

    func testNegativeDeclaredSeamsClampToZero() {
        let report = analyzer.analyze(declaredSeams: -7, usages: [])
        XCTAssertEqual(report.declaredSeams, 0)
        XCTAssertNil(report.surfaceRatio)
    }

    func testNegativeSiteCountClampsToZeroAndIsNotLive() {
        let usage = CapabilityUsage(
            capability: .urlCache, module: "ImageLoading",
            siteCount: -12, routing: .bypassesSeam, fallback: .none
        )
        XCTAssertEqual(usage.siteCount, 0)
        XCTAssertFalse(usage.isLive)

        let report = analyzer.analyze(declaredSeams: 1, usages: [usage])
        XCTAssertEqual(report.effectiveSurface, 0, "A zero-site record is inventory noise")
        XCTAssertEqual(report.verdict, .cheap(cost: 0))
    }

    func testZeroSiteCapabilityDoesNotBlockEvenWithoutFallback() {
        let usage = CapabilityUsage(
            capability: .backgroundTransfer, module: "MediaDownloader",
            siteCount: 0, routing: .bypassesSeam, fallback: .none
        )
        let report = analyzer.analyze(declaredSeams: 1, usages: [usage])
        XCTAssertEqual(report.verdict.label, "CHEAP")
    }

    func testReportIndexAccessIsBoundsChecked() {
        let report = SampleInventory.report()
        XCTAssertNil(report.usage(at: -1))
        XCTAssertNil(report.usage(at: report.usages.count))
        XCTAssertNotNil(report.usage(at: 0))
    }

    // MARK: - Merging

    func testDuplicateRecordsMergeWithWorstSeverityWinning() {
        let good = CapabilityUsage(
            capability: .sharedCookieStorage, module: "Checkout",
            siteCount: 9, routing: .throughSeam,
            fallback: .implemented("own cookie jar")
        )
        let bad = CapabilityUsage(
            capability: .sharedCookieStorage, module: "Checkout",
            siteCount: 1, routing: .bypassesSeam, fallback: .none
        )

        let merged = PortabilityAnalyzer.merge([good, bad])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].siteCount, 10, "Site counts add")
        XCTAssertEqual(merged[0].routing, .bypassesSeam, "One bypass makes it a bypass")
        XCTAssertEqual(merged[0].fallback, .none, "The weakest plan is the real plan")
    }

    func testMergeIsOrderIndependentForSeverity() {
        let good = CapabilityUsage(
            capability: .taskMetrics, module: "Observability",
            siteCount: 2, routing: .throughSeam, fallback: .documented("plan")
        )
        let bad = CapabilityUsage(
            capability: .taskMetrics, module: "Observability",
            siteCount: 3, routing: .bypassesSeam, fallback: .none
        )
        let forward = PortabilityAnalyzer.merge([good, bad])
        let reverse = PortabilityAnalyzer.merge([bad, good])
        XCTAssertEqual(forward[0].routing, reverse[0].routing)
        XCTAssertEqual(forward[0].fallback, reverse[0].fallback)
        XCTAssertEqual(forward[0].siteCount, reverse[0].siteCount)
    }

    func testSameCapabilityInDifferentModulesDoesNotMerge() {
        let a = CapabilityUsage(
            capability: .urlCache, module: "ImageLoading",
            siteCount: 3, routing: .throughSeam, fallback: .implemented("x")
        )
        let b = CapabilityUsage(
            capability: .urlCache, module: "FeedSync",
            siteCount: 2, routing: .throughSeam, fallback: .implemented("x")
        )
        XCTAssertEqual(PortabilityAnalyzer.merge([a, b]).count, 2)
    }

    // MARK: - The policy

    func testCurrencyTypesOnlyIsCheapEvenAtHighVolume() {
        let usages = [
            CapabilityUsage(capability: .requestResponseValues, module: "APIClient",
                            siteCount: 400, routing: .throughSeam, fallback: .implemented("values")),
            CapabilityUsage(capability: .jsonCoding, module: "APIClient",
                            siteCount: 300, routing: .bypassesSeam, fallback: .none)
        ]
        let report = analyzer.analyze(declaredSeams: 1, usages: usages)
        XCTAssertEqual(report.verdict.label, "CHEAP",
                       "Currency types bypassing the seam still port; that is what makes them currency")
    }

    func testPlatformServiceWithNoFallbackBlocksRegardlessOfCleanRouting() {
        let usage = CapabilityUsage(
            capability: .backgroundTransfer, module: "MediaDownloader",
            siteCount: 1, routing: .throughSeam, fallback: .none
        )
        let report = analyzer.analyze(declaredSeams: 1, usages: [usage])
        XCTAssertEqual(report.verdict.label, "BLOCKED")
        XCTAssertTrue(report.verdict.notes.contains { $0.contains("Background transfer") })
        XCTAssertTrue(report.verdict.notes.contains { $0.contains("MediaDownloader") })
    }

    func testDocumentedFallbackDowngradesBlockedToStageable() {
        let usage = CapabilityUsage(
            capability: .backgroundTransfer, module: "MediaDownloader",
            siteCount: 1, routing: .throughSeam,
            fallback: .documented("resumable download queue")
        )
        XCTAssertEqual(analyzer.analyze(declaredSeams: 1, usages: [usage]).verdict.label, "STAGEABLE")
    }

    func testImplementedFallbackThroughSeamIsCheap() {
        let usage = CapabilityUsage(
            capability: .backgroundTransfer, module: "MediaDownloader",
            siteCount: 12, routing: .throughSeam,
            fallback: .implemented("own resumable queue, shipping since March")
        )
        XCTAssertEqual(analyzer.analyze(declaredSeams: 1, usages: [usage]).verdict.label, "CHEAP")
    }

    func testProtocolLayerBypassIsStageableNotBlocked() {
        let usage = CapabilityUsage(
            capability: .tlsTrustEvaluation, module: "Networking",
            siteCount: 2, routing: .bypassesSeam, fallback: .implemented("pins in config")
        )
        XCTAssertEqual(analyzer.analyze(declaredSeams: 1, usages: [usage]).verdict.label, "STAGEABLE")
    }

    // MARK: - Cost behaviour

    func testBypassCostsMoreThanSeamRoutedAtIdenticalVolume() {
        let seam = CapabilityUsage(capability: .urlCache, module: "M",
                                   siteCount: 5, routing: .throughSeam, fallback: .none)
        let bypass = CapabilityUsage(capability: .urlCache, module: "M",
                                     siteCount: 5, routing: .bypassesSeam, fallback: .none)
        XCTAssertGreaterThan(analyzer.contribution(of: bypass), analyzer.contribution(of: seam))
    }

    func testRealFallbackLowersCost() {
        let noPlan = CapabilityUsage(capability: .urlCache, module: "M",
                                     siteCount: 5, routing: .throughSeam, fallback: .none)
        let built = CapabilityUsage(capability: .urlCache, module: "M", siteCount: 5,
                                    routing: .throughSeam, fallback: .implemented("own cache"))
        XCTAssertLessThan(analyzer.contribution(of: built), analyzer.contribution(of: noPlan))
    }

    func testCostIsMonotonicInSiteCount() {
        let small = CapabilityUsage(capability: .cellularPolicy, module: "M",
                                    siteCount: 1, routing: .throughSeam, fallback: .none)
        let large = CapabilityUsage(capability: .cellularPolicy, module: "M",
                                    siteCount: 30, routing: .throughSeam, fallback: .none)
        XCTAssertGreaterThan(analyzer.contribution(of: large), analyzer.contribution(of: small))
    }

    func testSiteScalingIsSublinear() {
        // Thirty call sites must not cost thirty times one call site.
        let one = CostModel.default.siteScaling(1)
        let thirty = CostModel.default.siteScaling(30)
        XCTAssertLessThan(thirty, one * 30)
        XCTAssertGreaterThan(thirty, one)
    }

    func testCostByClassSumsToTotal() {
        let report = SampleInventory.report()
        let sum = report.costByClass().values.reduce(0, +)
        XCTAssertEqual(sum, report.migrationCost, accuracy: 0.0001)
    }

    func testPlatformServicesDominateCostInTheSampleApp() {
        let byClass = SampleInventory.report().costByClass()
        let platform = byClass[.platformService] ?? 0
        let currency = byClass[.currencyType] ?? 0
        XCTAssertGreaterThan(platform, currency,
                             "The expensive half of a migration is the half that was never HTTP")
    }

    // MARK: - The headline claim

    func testSampleAppSurfaceIsFarWiderThanItsDeclaredSeam() {
        let report = SampleInventory.report()
        XCTAssertEqual(report.declaredSeams, 1)
        XCTAssertGreaterThanOrEqual(report.effectiveSurface, 12)
        XCTAssertEqual(report.surfaceRatio ?? 0, Double(report.effectiveSurface), accuracy: 0.0001)
        XCTAssertEqual(report.verdict.label, "BLOCKED")
    }

    func testSampleAppBlocksOnCapabilitiesThatWereNeverHTTP() {
        let notes = SampleInventory.report().verdict.notes.joined(separator: " ")
        XCTAssertTrue(notes.contains("Shared cookie storage"))
        XCTAssertTrue(notes.contains("System credential store"))
        XCTAssertTrue(notes.contains("Background transfer"))
        XCTAssertTrue(notes.contains("Per-task transfer metrics"))
    }

    func testSummaryLineIsStableAndReadable() {
        let line = SampleInventory.report().summaryLine()
        XCTAssertTrue(line.hasPrefix("MEASURED —"))
        XCTAssertTrue(line.contains("declared seams: 1"))
        XCTAssertTrue(line.contains("verdict: BLOCKED"))
    }

    func testCodableRoundTripPreservesUsage() throws {
        let original = SampleInventory.usages[0]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CapabilityUsage.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
