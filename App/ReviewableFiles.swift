import FeatureAIReview
import FeatureDiff

/// Bridges the diff slice to the AI review slice (composition root only).
nonisolated enum ReviewableFiles {
    static func make(from files: [FileDiff]) -> [ReviewableFile] {
        files.filter { !$0.isBinary }.map { file in
            var changed = Set<Int>()
            var visible = Set<Int>()
            var patch: [String] = []
            for hunk in file.hunks {
                patch.append(hunk.header)
                for line in hunk.lines {
                    switch line.kind {
                    case .added:
                        patch.append("+" + line.text)
                        if let number = line.newNumber {
                            changed.insert(number)
                            visible.insert(number)
                        }
                    case .removed:
                        patch.append("-" + line.text)
                    case .context:
                        patch.append(" " + line.text)
                        if let number = line.newNumber { visible.insert(number) }
                    }
                }
            }
            return ReviewableFile(
                path: file.path, patch: patch.joined(separator: "\n"), changedNewLines: changed,
                visibleNewLines: visible,
                isNoise: file.kind.isNoise)
        }
    }
}
