import Foundation
import Platform
import SylvraCore

/// Deliveries survive a restart: the inbox shows the stages and outcome of merged pull requests right away,
/// without opening each one.
extension DeliveryModel {
    static let deliveriesKey = "deliveries"
    /// Kept at most: the most recently merged.
    static let keptDeliveries = 60

    static func restoredDeliveries(from cache: JSONCache?) -> [PullRequestID: Delivery] {
        let saved = cache?.load([Delivery].self, key: deliveriesKey) ?? []
        return Dictionary(saved.map { ($0.pullRequest, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func saveDeliveries() {
        guard let cache else { return }
        let newest = deliveries.values.sorted { ($0.mergedAt ?? .distantPast) > ($1.mergedAt ?? .distantPast) }
            .prefix(Self.keptDeliveries)
        cache.saveInBackground(Array(newest), key: Self.deliveriesKey)
    }

    /// Loads the deliveries of pull requests the inbox lists as recently closed (merged ones get one), so their
    /// rows show it without being opened. Each at most once per launch, unless it is still on its way.
    public func preload(_ ids: [PullRequestID], now: Date = .now) async {
        for id in ids.prefix(Self.preloadLimit) {
            if let known = deliveries[id], known.isFinished(at: now) { continue }
            if deliveries[id] == nil, preloaded.contains(id) { continue }
            preloaded.insert(id)
            guard let loaded = try? await loader.loadDelivery(for: id), deliveries[id] != loaded else { continue }
            deliveries[id] = loaded
            saveDeliveries()
        }
    }

    static let preloadLimit = 15

    /// Restored deliveries that were still on their way may have moved on while Sylvra was closed: loaded once
    /// at launch (followed ones are reloaded by the follower anyway).
    func refreshRestored(now: Date = .now) async {
        let stale = deliveries.values.filter { !$0.isFinished(at: now) && !isFollowing($0.pullRequest) }
            .map(\.pullRequest)
        for id in stale {
            guard let loaded = try? await loader.loadDelivery(for: id) else { continue }
            if deliveries[id] != loaded {
                deliveries[id] = loaded
                saveDeliveries()
            }
        }
    }
}
