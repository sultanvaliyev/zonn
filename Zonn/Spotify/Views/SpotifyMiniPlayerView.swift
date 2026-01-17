import SwiftUI
import AppKit

/// A minimal Spotify player view for compact window layouts.
/// Shows track info and essential controls (play/pause, skip) in a horizontal layout.
struct SpotifyMiniPlayerView: View {
    @ObservedObject var spotifyManager: SpotifyManager

    var body: some View {
        Group {
            if spotifyManager.isConnected {
                connectedView
            } else {
                disconnectedView
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var connectedView: some View {
        HStack(spacing: 10) {
            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(spotifyManager.trackName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.textOnGreen)
                    .lineLimit(1)

                if !spotifyManager.artistName.isEmpty {
                    Text(spotifyManager.artistName)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textOnGreenSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Mini controls
            HStack(spacing: 6) {
                // Previous track
                Button(action: { Task { await spotifyManager.previousTrack() } }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Previous track")

                // Play/Pause
                Button(action: { Task { await spotifyManager.togglePlayPause() } }) {
                    Image(systemName: spotifyManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help(spotifyManager.isPlaying ? "Pause" : "Play")

                // Next track
                Button(action: { Task { await spotifyManager.nextTrack() } }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Next track")
            }
        }
    }

    private var disconnectedView: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 14))
                .foregroundColor(AppColors.textOnGreenSecondary)

            Text("Spotify not connected")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppColors.textOnGreenSecondary)

            Spacer()

            Button(action: openSpotify) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color(red: 0.11, green: 0.72, blue: 0.33))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func openSpotify() {
        guard let spotifyURL = URL(string: "spotify:") else { return }

        // Check if Spotify is installed before trying to open
        if NSWorkspace.shared.urlForApplication(toOpen: spotifyURL) != nil {
            NSWorkspace.shared.open(spotifyURL)

            // Start a delayed refresh to detect when Spotify launches
            Task {
                // Wait a moment for Spotify to start launching
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

                // Request automation permission - this triggers the macOS prompt if needed
                await spotifyManager.requestPermission()

                // Now try to connect with retries
                for _ in 0..<10 {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                    await spotifyManager.refresh()
                    if spotifyManager.isConnected {
                        // Spotify is now running, ensure polling is active
                        if !spotifyManager.isPolling {
                            spotifyManager.startPolling()
                        }
                        break
                    }
                }
            }
        }
    }
}

#Preview("Connected") {
    SpotifyMiniPlayerView(spotifyManager: SpotifyManager(service: MockSpotifyService.playing()))
        .padding()
        .background(AppColors.forestGreen)
        .frame(width: 260)
}

#Preview("Disconnected") {
    SpotifyMiniPlayerView(spotifyManager: SpotifyManager(service: MockSpotifyService.disconnected()))
        .padding()
        .background(AppColors.forestGreen)
        .frame(width: 260)
}
