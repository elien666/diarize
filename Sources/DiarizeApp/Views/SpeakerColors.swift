import SwiftUI

/// Deterministic color per speaker ID. Hashing → palette index.
enum SpeakerColors {
    private static let palette: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint, .cyan, .red, .brown
    ]

    static func color(for speakerId: String) -> Color {
        var hash: UInt64 = 5381
        for byte in speakerId.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return palette[Int(hash % UInt64(palette.count))]
    }
}
