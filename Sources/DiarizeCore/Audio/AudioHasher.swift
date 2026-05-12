import CryptoKit
import Foundation

public enum AudioHasher {
    /// SHA-256 of the file contents, returned as lowercase hex.
    /// Used to detect that an MP3 has already been transcribed (Resume/Skip).
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 1024 * 1024
        while autoreleasepool(invoking: { () -> Bool in
            let data = handle.readData(ofLength: chunkSize)
            if data.isEmpty { return false }
            hasher.update(data: data)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
