import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioPlayer: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying: Bool = false

    private(set) var loadedURL: URL?
    private var player: AVPlayer?
    private var timeObserver: Any?

    func load(url: URL) {
        // Avoid reloading the same file (would interrupt playback / reset position).
        if loadedURL == url, player != nil { return }
        loadFresh(url: url)
    }

    /// Force a reload even if URL matches (e.g. after a recording finished and the file
    /// changed under us — the previous AVPlayerItem may have cached duration=0).
    func forceReload(url: URL) {
        loadFresh(url: url)
    }

    private func loadFresh(url: URL) {
        cleanup()
        loadedURL = url
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        self.player = p
        Task {
            do {
                let dur = try await item.asset.load(.duration)
                self.duration = CMTimeGetSeconds(dur)
            } catch {
                self.duration = 0
            }
        }
        installTimeObserver(on: p)
    }

    func play() {
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlay() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to seconds: Double) {
        guard let p = player else { return }
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        p.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
        currentTime = seconds
    }

    private func installTimeObserver(on player: AVPlayer) {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = CMTimeGetSeconds(time)
            Task { @MainActor in self?.currentTime = seconds }
        }
        self.timeObserver = token
    }

    private func cleanup() {
        if let token = timeObserver, let p = player {
            p.removeTimeObserver(token)
        }
        player?.pause()
        player = nil
        timeObserver = nil
        loadedURL = nil
        currentTime = 0
        duration = 0
        isPlaying = false
    }
}
