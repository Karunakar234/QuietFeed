import AVFAudio
import Foundation
import Observation

struct OfflineTrack: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var fileName: String
    var importedAt: Date
}

@MainActor
@Observable
final class OfflineAudioLibrary {
    private(set) var tracks: [OfflineTrack] = []
    private(set) var playingTrackID: UUID?
    private(set) var isPlaying = false
    private(set) var lastError: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    private let folderURL: URL
    private let manifestURL: URL

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        let base = directory ?? (fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory).appendingPathComponent("QuietFeed", isDirectory: true)
        folderURL = base.appendingPathComponent("Offline Audio", isDirectory: true)
        manifestURL = folderURL.appendingPathComponent("library.json")
        if let data = try? Data(contentsOf: manifestURL),
           let saved = try? JSONDecoder().decode([OfflineTrack].self, from: data) {
            tracks = saved.filter { fileManager.fileExists(atPath: folderURL.appendingPathComponent($0.fileName).path) }
        }
    }

    func importAudio(from sourceURL: URL) {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let id = UUID()
            let ext = sourceURL.pathExtension.isEmpty ? "audio" : sourceURL.pathExtension.lowercased()
            let fileName = "\(id.uuidString).\(ext)"
            let destination = folderURL.appendingPathComponent(fileName)
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            tracks.append(OfflineTrack(
                id: id,
                title: sourceURL.deletingPathExtension().lastPathComponent,
                fileName: fileName,
                importedAt: .now
            ))
            persist()
            lastError = nil
        } catch {
            lastError = "The audio file could not be imported."
        }
    }

    func togglePlayback(of track: OfflineTrack) {
        if playingTrackID == track.id, let player {
            if player.isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
            return
        }

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: folderURL.appendingPathComponent(track.fileName))
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
            playingTrackID = track.id
            isPlaying = true
            lastError = nil
        } catch {
            playingTrackID = nil
            isPlaying = false
            lastError = "This audio format could not be played."
        }
    }

    func remove(_ track: OfflineTrack) {
        if playingTrackID == track.id {
            player?.stop()
            player = nil
            playingTrackID = nil
            isPlaying = false
        }
        try? FileManager.default.removeItem(at: folderURL.appendingPathComponent(track.fileName))
        tracks.removeAll { $0.id == track.id }
        persist()
    }

    func reset() {
        player?.stop()
        player = nil
        playingTrackID = nil
        isPlaying = false
        try? FileManager.default.removeItem(at: folderURL)
        tracks = []
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try JSONEncoder().encode(tracks).write(to: manifestURL, options: .atomic)
        } catch {
            assertionFailure("Unable to persist offline audio library: \(error)")
        }
    }
}
