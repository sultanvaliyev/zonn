import SwiftUI

/// View displayed when Spotify automation permission is needed or denied.
/// Provides clear instructions and actions based on the current permission state.
struct SpotifyPermissionView: View {
    // MARK: - Properties

    @ObservedObject var spotifyManager: SpotifyManager
    @State private var isRequestingPermission = false
    @State private var isCheckingStatus = false
    @State private var showingDeniedInstructions = false

    /// Whether permission has been explicitly denied (vs just not determined)
    private var isPermissionDenied: Bool {
        spotifyManager.permissionStatus == .denied
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            // Icon - different based on state
            Image(systemName: isPermissionDenied ? "xmark.shield.fill" : "lock.shield.fill")
                .font(.system(size: 28))
                .foregroundColor(isPermissionDenied ? AppColors.warning : AppColors.spotifyGreen)

            // Title
            Text(isPermissionDenied ? "Permission Denied" : "Permission Required")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.textOnGreen)

            // Description - context-sensitive
            Text(descriptionText)
                .font(.system(size: 12))
                .foregroundColor(AppColors.textOnGreenSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Action buttons - different layout based on state
            if isPermissionDenied {
                deniedStateButtons
            } else {
                notDeterminedStateButtons
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Description Text

    private var descriptionText: String {
        if isPermissionDenied {
            return "Automation access was denied. To enable Spotify controls, please grant permission in System Settings > Privacy & Security > Automation."
        } else {
            return "Zonn needs automation permission to control Spotify playback. A system dialog will appear when you tap Grant Permission."
        }
    }

    // MARK: - Not Determined State Buttons

    private var notDeterminedStateButtons: some View {
        VStack(spacing: 8) {
            // Primary: Grant Permission button
            Button(action: requestPermission) {
                HStack(spacing: 6) {
                    if isRequestingPermission {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 12))
                    }
                    Text("Grant Permission")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(AppColors.spotifyGreen)
                )
            }
            .buttonStyle(.plain)
            .disabled(isRequestingPermission)
            .help("Request permission to control Spotify")
        }
        .padding(.top, 4)
    }

    // MARK: - Denied State Buttons

    private var deniedStateButtons: some View {
        VStack(spacing: 10) {
            // Primary: Open System Settings button (more prominent when denied)
            Button(action: openSettings) {
                HStack(spacing: 6) {
                    Image(systemName: "gear")
                        .font(.system(size: 12))
                    Text("Open System Settings")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(AppColors.spotifyGreen)
                )
            }
            .buttonStyle(.plain)
            .help("Open System Settings to grant automation permission")

            // Secondary: Re-check permission status
            Button(action: recheckPermission) {
                HStack(spacing: 4) {
                    if isCheckingStatus {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    Text("Check Again")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(AppColors.textOnGreenSecondary)
            }
            .buttonStyle(.plain)
            .disabled(isCheckingStatus)
            .help("Re-check if permission has been granted in System Settings")

            // Expandable instructions
            DisclosureGroup(
                isExpanded: $showingDeniedInstructions,
                content: {
                    VStack(alignment: .leading, spacing: 6) {
                        instructionRow(number: "1", text: "Open System Settings")
                        instructionRow(number: "2", text: "Go to Privacy & Security")
                        instructionRow(number: "3", text: "Select Automation")
                        instructionRow(number: "4", text: "Find Zonn and enable Spotify")
                        instructionRow(number: "5", text: "Return here and tap \"Check Again\"")
                    }
                    .padding(.top, 8)
                },
                label: {
                    Text("How to enable")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppColors.textOnGreenSecondary)
                }
            )
            .tint(AppColors.textOnGreenSecondary)
        }
        .padding(.top, 4)
    }

    // MARK: - Instruction Row Helper

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.spotifyGreen)
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(AppColors.spotifyGreen.opacity(0.2))
                )

            Text(text)
                .font(.system(size: 11))
                .foregroundColor(AppColors.textOnGreenSecondary)

            Spacer()
        }
    }

    // MARK: - Actions

    private func requestPermission() {
        isRequestingPermission = true

        Task {
            let granted = await spotifyManager.requestPermission()
            isRequestingPermission = false

            // If granted, try to connect
            if granted {
                await spotifyManager.refresh()
                if spotifyManager.isConnected && !spotifyManager.isPolling {
                    spotifyManager.startPolling()
                }
            }
        }
    }

    private func openSettings() {
        spotifyManager.openSystemSettings()
    }

    private func recheckPermission() {
        isCheckingStatus = true

        Task {
            // Re-check permission status
            await spotifyManager.checkPermission()

            // If now authorized, try to connect
            if spotifyManager.permissionStatus == .authorized {
                await spotifyManager.refresh()
                if spotifyManager.isConnected && !spotifyManager.isPolling {
                    spotifyManager.startPolling()
                }
            }

            isCheckingStatus = false
        }
    }
}

// MARK: - Previews

#Preview("Permission Required") {
    let mockService = MockSpotifyService.disconnected()
    let manager = SpotifyManager(service: mockService)

    return SpotifyPermissionView(spotifyManager: manager)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.spotifyWidgetBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.spotifyWidgetBorder, lineWidth: 1)
                )
        )
        .padding()
        .background(AppColors.forestGreen)
        .frame(width: 300)
}

#Preview("In Widget Context") {
    let mockService = MockSpotifyService.disconnected()
    let manager = SpotifyManager(service: mockService)

    return VStack {
        SpotifyPermissionView(spotifyManager: manager)
    }
    .padding(16)
    .background(
        RoundedRectangle(cornerRadius: 12)
            .fill(AppColors.spotifyWidgetBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColors.spotifyWidgetBorder, lineWidth: 1)
            )
    )
    .padding()
    .background(AppColors.forestGreen)
    .frame(width: 300)
}
