/// How the AI writing helper changes a review comment draft.
public enum CommentRewriteStyle: String, Sendable, CaseIterable {
    /// Better wording, personal and friendly, still short.
    case improve
    /// As short and crisp as possible.
    case shorten
    /// Only translate into the comment language; keep the wording.
    case translate
}
