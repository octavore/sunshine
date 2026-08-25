# Sunshine

Auto-update library for macOS apps distributed via GitHub Releases, similar in
purpose to Sparkle or the Tauri updater. It does not use a separate signing
key. Instead it verifies updates using macOS code signing and notarization:
an update is installed only if it is signed by the same Developer ID Team as
the app currently running.

## Requirements

- macOS 13+
- Swift tools 6.0+
- The app must be Developer ID signed and notarized, distributed outside the
  Mac App Store. Self-replacing the app bundle does not work under App
  Sandbox and is not allowed on the App Store. Sunshine returns
  `SunshineError.sandboxedAppUnsupported` if it detects a sandboxed app.
- Apple Silicon and universal binaries only. Intel-only release assets are
  not selected.
- Release assets must be a `.zip` or `.dmg` containing a single top-level
  `.app`.

## Installation

Add Sunshine as a Swift Package dependency:

```swift
.package(url: "https://github.com/<you>/sunshine.git", from: "1.0.0")
```

Two products are available:

- `Sunshine` — core engine plus the SwiftUI update UI.
- `SunshineCore` — core engine only, no SwiftUI/AppKit dependency.

## Naming release assets

Assets are filtered by architecture before anything else. Name release
assets so they contain `arm64`, `apple-silicon`, or `universal`, or omit an
architecture entirely if you only publish one build:

```
MyApp-1.4.2-arm64.zip
MyApp-1.4.2-universal.dmg
```

Assets naming `x86_64`, `x64`, or `intel` are excluded.

## Required startup hook

Add this line as early as possible in app startup (e.g.
`applicationDidFinishLaunching`), for both UI and headless integrations. It
confirms a pending relaunch from a previous update:

```swift
import SunshineCore

func applicationDidFinishLaunching(_ notification: Notification) {
    SunshineUpdater.confirmSuccessfulRelaunchIfNeeded()
    // ...
}
```

If this is omitted, Sunshine falls back to checking whether a process with
the app's bundle ID is running, which is a weaker signal of relaunch success.

## Usage: SwiftUI

```swift
import SwiftUI
import Sunshine

@main
struct MyApp: App {
    @StateObject private var updaterUI = SunshineUpdaterUIController(
        updater: SunshineUpdater(configuration: SunshineConfiguration(
            owner: "acme",
            repo: "myapp",
            checkInterval: 3600 // check hourly; omit to only check when called explicitly
        ))
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .sunshineUpdater(updaterUI)
        .commands {
            CheckForUpdatesCommand(updaterUI) // adds "Check for Updates…" to the app menu
        }
    }
}
```

`.sunshineUpdater(_:)` attaches the update sheet and starts the background
check loop if `checkInterval` is set. The sheet shows the app icon, version
diff, rendered release notes, and Install & Relaunch / Remind Me Later / Skip
This Version actions.

## Usage: headless

Depend on `SunshineCore` alone and drive the pipeline directly:

```swift
import SunshineCore

let updater = SunshineUpdater(configuration: SunshineConfiguration(
    owner: "acme",
    repo: "myapp",
    automationLevel: .autoDownloadAndInstall // or .manual / .autoDownload
))

// One-shot, fully automatic:
try await updater.checkDownloadVerifyAndInstall(silently: true)

// Or drive each step directly, e.g. for custom UI:
let result = await updater.checkForUpdates()
if case .updateAvailable(let update) = result {
    let downloaded = try await updater.download(update)
    let verified = try await updater.verify(downloaded)
    try await updater.install(verified) // quits, swaps, relaunches; does not return on success
}

// Or observe progress via the event stream:
for await event in updater.events {
    switch event {
    case .downloadProgress(let fraction, _, _): print("Downloading: \(fraction)")
    case .verificationFinished(.failure(let error)): print("Verification failed: \(error)")
    default: break
    }
}
```

`SunshineUpdaterDelegate` is also available as a callback-style alternative
to the event stream.

## Configuration reference

`SunshineConfiguration` fields (`owner`/`repo` required, the rest optional):

| Field | Default | Purpose |
|---|---|---|
| `owner`, `repo` | — | GitHub repository to check for releases |
| `allowPrereleases` | `false` | Consider releases marked "prerelease" |
| `assetMatcher` | `.zipOrDmgContainingApp()` | How to pick an asset from a release; also accepts `.regex` or `.custom` |
| `githubToken` | `nil` | Raises the API rate limit from 60/hr to 5000/hr; recommended if checking more than hourly |
| `checkInterval` | `nil` | Seconds between automatic background checks; `nil` disables automatic checking |
| `installLocation` | `nil` | Overrides the install path; defaults to `Bundle.main.bundleURL` |
| `requireNotarization` | `true` | Also require a passing Gatekeeper/notarization check, not just a Team ID match |
| `automationLevel` | `.manual` | `.manual` (prompt only), `.autoDownload` (auto-download, prompt to install), or `.autoDownloadAndInstall` (fully silent) |

Automatic checks run on launch (rate-limited) and every `checkInterval`
seconds, with exponential backoff on repeated failures.

## How verification and install work

1. Check: fetch the latest (or, if prereleases are allowed, most recent
   qualifying) GitHub release, compare its tag against the running app's
   version. An update is available only if the candidate version is strictly
   newer than the running version.
2. Download: fetch the matched asset to a per-app cache directory.
3. Verify: extract the `.app`, check its code signature is valid, and check
   its Team ID matches the currently running app's Team ID (read live via
   `SecCodeCopySelf`, not from cached config). If `requireNotarization` is
   set, also check notarization/Gatekeeper acceptance. Any failure here
   rejects the update.
4. Install: while the app is still running, move the old bundle aside, move
   the verified new bundle into place, clear its quarantine flag, launch it,
   and wait for it to confirm it started. If any step fails, roll back to the
   old bundle and leave the running app in place.

`install()` requires the install location to be writable by the current
user. There is no privileged-helper fallback: if the location isn't
writable, it returns `SunshineError.installLocationNotWritable` along with
the release's page URL for a manual download.

## Development

This project uses [axo](https://github.com) for task running:

```
axo build   # swift build
axo test    # swift test
axo clean   # swift package clean
```

## Remaining work

The core engine, installer, verification, and both UI/headless integration
paths are implemented and covered by unit tests (25 passing: version
comparison, asset matching, verification logic, install session). Not done:

- Manual end-to-end testing against a real signed/notarized app. Unit tests
  mock code signing and the relaunch handshake; the full pipeline has not
  been run against a real Developer ID identity. This needs:
  - A small throwaway demo app, signed and notarized, published as two
    GitHub releases at different versions (one as `.zip`, one as `.dmg`) to
    exercise both extraction paths.
  - A run of the full check → download → verify → install → relaunch flow,
    confirming the relaunched app reports the new version and the old bundle
    is removed.
  - A forced rollback (break the relaunch handshake, or block the
    destination path) to confirm the old app keeps running.
  - A permission-denied install location, to confirm the error path with no
    partial file operations.
  - Confirming `com.apple.quarantine` is present after download/extraction
    and absent after install.
  - A deliberately corrupted binary and a build signed with a different Team
    ID, to confirm both are rejected before any install step runs.
- No CI workflow for running `swift test` on push.
- No versioned release of the package.
- Deferred from the original design, out of scope for v1: a separate
  relaunch-helper process (the current approach is an in-process
  `NSWorkspace` launch plus a sentinel-file handshake), a privileged
  installer helper for non-writable install locations, `.pkg` asset support,
  and staged/percentage rollouts.
