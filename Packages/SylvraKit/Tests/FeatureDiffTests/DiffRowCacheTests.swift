import Testing

@testable import FeatureDiff

@MainActor
struct DiffRowCacheTests {
    let hunks = [
        Hunk(
            oldStart: 1, oldCount: 2, newStart: 1, newCount: 2,
            lines: [
                DiffLine(kind: .context, oldNumber: 1, newNumber: 1, text: "a"),
                DiffLine(kind: .removed, oldNumber: 2, newNumber: nil, text: "b"),
                DiffLine(kind: .added, oldNumber: nil, newNumber: 2, text: "c"),
            ])
    ]

    @Test func buildsTheSameRowsAsWithoutCache() {
        let cache = DiffRowCache()
        for layout in DiffScreenModel.Layout.allCases {
            let cached = cache.rows(path: "a.swift", hunks: hunks, layout: layout).map(\.id)
            let direct = DiffRow.identifiedRows(path: "a.swift", hunks: hunks, layout: layout).map(\.id)
            #expect(cached == direct)
        }
    }

    @Test func rebuildsWhenHunksOrLayoutChange() {
        let cache = DiffRowCache()
        #expect(cache.rows(path: "a.swift", hunks: hunks, layout: .inline).count == 4)
        #expect(cache.rows(path: "a.swift", hunks: hunks, layout: .sideBySide).count == 3)
        var changed = hunks
        changed[0].lines.append(DiffLine(kind: .added, oldNumber: nil, newNumber: 3, text: "d"))
        #expect(cache.rows(path: "a.swift", hunks: changed, layout: .sideBySide).count == 4)
        #expect(cache.rows(path: "a.swift", hunks: [], layout: .sideBySide).isEmpty)
    }
}
