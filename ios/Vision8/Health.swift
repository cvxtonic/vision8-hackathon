import HealthKit

/// Reads today's steps and this morning's weight from the Health app for KPIs with source "steps" / "weight".
enum Health {
    private static let store = HKHealthStore()
    private static let steps = HKQuantityType(.stepCount)
    private static let weight = HKQuantityType(.bodyMass)

    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Asks once for read access; iOS does not tell whether reading was allowed, so missing data just reads as nil.
    static func authorize() async -> Bool {
        guard available else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [steps, weight])
            return true
        } catch {
            return false
        }
    }

    /// Today's value for a KPI source, or nil when the Health app has none (yet).
    static func today(_ source: String) async -> Double? {
        let start = Calendar.current.startOfDay(for: .now)
        let range = HKQuery.predicateForSamples(withStart: start, end: .now)
        switch source {
        case "steps":
            let query = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: steps, predicate: range), options: .cumulativeSum)
            guard let sum = try? await query.result(for: store)?.sumQuantity() else { return nil }
            return sum.doubleValue(for: .count()).rounded()
        case "weight":
            let query = HKSampleQueryDescriptor(predicates: [.quantitySample(type: weight, predicate: range)], sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1)
            guard let sample = try? await query.result(for: store).first else { return nil }
            return (sample.quantity.doubleValue(for: .gramUnit(with: .kilo)) * 10).rounded() / 10
        default:
            return nil
        }
    }
}
