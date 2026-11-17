import Testing

@testable import FeatureDiff

struct DiffCopyTests {
    let hunk = Hunk(
        oldStart: 8, oldCount: 3, newStart: 8, newCount: 3,
        lines: [
            DiffLine(kind: .context, oldNumber: 8, newNumber: 8, text: "func total() {"),
            DiffLine(kind: .removed, oldNumber: 9, newNumber: nil, text: "    old()"),
            DiffLine(kind: .added, oldNumber: nil, newNumber: 9, text: "    new()"),
            DiffLine(kind: .context, oldNumber: 10, newNumber: 10, text: "}"),
        ])

    @Test func copiesEitherVersionOfTheCode() {
        #expect(DiffCopy.code(hunk.lines, version: .new) == "func total() {\n    new()\n}")
        #expect(DiffCopy.code(hunk.lines, version: .old) == "func total() {\n    old()\n}")
    }

    @Test func copiesTheHunkAsAUnifiedDiff() {
        #expect(DiffCopy.unified(hunk) == "@@ -8,3 +8,3 @@\n func total() {\n-    old()\n+    new()\n }")
    }
}
