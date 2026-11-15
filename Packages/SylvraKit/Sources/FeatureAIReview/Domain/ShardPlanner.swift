import Foundation

/// Splits a PR into shards for parallel agents (see specs/architecture.md §8.5).
public enum ShardPlanner {
    public struct Shard: Hashable, Sendable {
        public let name: String
        public let files: [ReviewableFile]
    }

    /// Groups files by folder, keeps tests with their sources' folder name, balances by size.
    public static func plan(_ files: [ReviewableFile], maxShards: Int, threshold: Int) -> [Shard] {
        let reviewable = files.filter { !$0.isNoise }
        let total = reviewable.reduce(0) { $0 + $1.changedNewLines.count }
        guard maxShards > 1, total >= threshold, reviewable.count > 1 else {
            return reviewable.isEmpty ? [] : [Shard(name: String(localized: "Whole PR"), files: reviewable)]
        }

        // Group by top two path components, then distribute groups greedily onto the lightest shard.
        var groups: [String: [ReviewableFile]] = [:]
        for file in reviewable { groups[groupKey(file.path), default: []].append(file) }
        let sortedGroups = groups.sorted { lhs, rhs in
            lhs.value.reduce(0) { $0 + $1.weight } > rhs.value.reduce(0) { $0 + $1.weight }
        }
        let shardCount = min(maxShards, sortedGroups.count)
        var buckets = Array(repeating: (names: [String](), files: [ReviewableFile](), weight: 0), count: shardCount)
        for (key, files) in sortedGroups {
            guard let lightest = buckets.indices.min(by: { buckets[$0].weight < buckets[$1].weight }) else { continue }
            buckets[lightest].names.append(key)
            buckets[lightest].files += files
            buckets[lightest].weight += files.reduce(0) { $0 + $1.weight }
        }
        return buckets.filter { !$0.files.isEmpty }.map { bucket in
            Shard(
                name: bucket.names.map { ($0 as NSString).lastPathComponent }.joined(separator: " · "),
                files: bucket.files)
        }
    }

    /// Folder used for grouping; test folders map to the name of what they test where possible.
    static func groupKey(_ path: String) -> String {
        let components = (path as NSString).deletingLastPathComponent.split(separator: "/").map(String.init)
        let meaningful =
            components
            .filter { !["Sources", "Tests", "src", "test", "tests", "lib"].contains($0) }
            .map { $0.hasSuffix("Tests") ? String($0.dropLast(5)) : $0 }
            .filter { !$0.isEmpty }
        return meaningful.prefix(2).joined(separator: "/")
    }
}
