enum TableRow {
    /// Pad each cell to its column width (0 = no padding). Joined by two spaces.
    /// Avoids `String(format: "%s")` which expects a C-string and crashes with Swift `String`.
    static func format(_ cells: [String], widths: [Int]) -> String {
        zip(cells, widths)
            .map { cell, w in w > 0 ? cell.paddedRight(to: w) : cell }
            .joined(separator: "  ")
    }
}

private extension String {
    func paddedRight(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
