# Sunshine

Auto-update library for macOS apps distributed via GitHub Releases. Updates are verified using macOS code signing and notarization - an update is installed only if it is signed by the same Developer ID Team as the app currently running.

## Requirements

- macOS 13+
- Swift tools 6.0+
- The app must be Developer ID signed and notarized, distributed outside the
  Mac App Store. Self-replacing the app bundle does not work under App
  Sandbox.
- Apple Silicon and universal binaries only. Intel-only releases are ignored.
- Release assets must be a `.zip` or `.dmg` containing a single top-level
  `.app`.

## Installation

Add Sunshine as a Swift Package dependency:

```swift
.package(url: "https://github.com/octavore/sunshine.git", from: "1.0.0")
```

Two products are available:

- `Sunshine`: core engine plus the SwiftUI update UI.
- `SunshineCore`: core engine only, no SwiftUI/AppKit dependency.

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

If this is omitted, Sunshine falls back to checking whether the new bundle's
executable is running, which is a weaker signal of relaunch success.

`SunshineUpdater`'s initialiser calls this for you, so wiring it explicitly
only matters if you construct the updater lazily rather than at launch.

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

`.sunshineUpdater(_:)` attaches the update UI and starts the background
check loop if `checkInterval` is set. It defaults to a modal sheet showing
the app icon (auto-detected from `Bundle.main`'s `CFBundleIconFile`/
`CFBundleIconName`, or pass `appIcon:` to override), version diff, rendered
release notes, and Install & Relaunch / Remind Me Later / Skip This Version
actions. If there's no update, "Check for Updates…" (triggered via
`CheckForUpdatesCommand`) shows a "You're up to date!" alert instead.

### Less obtrusive: corner indicator

Pass `style: .cornerIndicator` to replace the auto-popping sheet with a
small badge pinned to the window's bottom-trailing corner. It only appears
when there's something to show (an update or an error) and stays out of the
way until the user opens it.

```swift
.sunshineUpdater(updaterUI, style: .cornerIndicator)
```

Tapping the badge opens the same update-review UI in a popover. The
"Check for Updates…" menu command still surfaces its result via alert/sheet
regardless of `style`, since it's a deliberate user action rather than a
passive notification.

### Settings pane

`SunshineUpdateSettingsView` is a prebuilt "Updates" pane for a `Settings`
scene. It shows app
identity, Automatically Check For Updates / Install Updates Automatically
toggles, a Stable/Pre-release channel picker, and a Check Now button with a
last-check timestamp. When a check finds an update, the review (release
notes, Install & Relaunch, Skip, Remind Me Later) appears inline in the pane:

```swift
Settings {
    SunshineUpdateSettingsView(controller: updaterUI)
}
```

Its toggles read and write live settings on `SunshineUpdater`
(`isAutomaticallyCheckingForUpdates`, `automationLevel`, `allowPrereleases`),
which persist to `UserDefaults` per bundle identifier and take effect
immediately, with no relaunch or extra wiring required. Pass
`showChannelPicker: false` to hide the prerelease picker.

Check Now routes through `controller.refreshUpdateStatus()`, so a version the
user previously skipped or deferred is resurfaced here rather than reported as
"up to date". While the pane is on screen it sets
`controller.suppressesUpdateSheet`, so an update it finds shows in the pane and
does not also pop as a sheet from `.sunshineUpdater` on another window; the
"Check for Updates…" menu command is unaffected when the pane is closed.

`SunshineUpdater` also exposes `skippedVersion` and `isRemindingLater` (both
read-only) for a host that wants to reflect that state in its own UI.

## Usage: headless

Depending on `SunshineCore` alone:

```swift
import SunshineCore

let updater = SunshineUpdater(configuration: SunshineConfiguration(
    owner: "acme",
    repo: "myapp",
    automationLevel: .autoDownloadAndInstall // or .manual / .autoDownload
))

// One-shot, fully automatic:
try await updater.checkDownloadVerifyAndInstall(silently: true)

// Or run each step directly, e.g. for custom UI:
let result = await updater.checkForUpdates()
if case .updateAvailable(let update) = result {
    let downloaded = try await updater.download(update)
    let verified = try await updater.verify(downloaded)
    try await updater.install(verified) // stages the swap, then terminates this process
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

### Live settings

`SunshineUpdater` exposes three settings from `SunshineConfiguration` as
mutable properties, so they can be changed at runtime (e.g. from a settings
UI) instead of only at construction. Each setter persists the new value to
`UserDefaults`, scoped per bundle identifier, and takes effect immediately:

```swift
updater.isAutomaticallyCheckingForUpdates // get/set; starts/stops the background loop
updater.automationLevel                   // get/set: .manual / .autoDownload / .autoDownloadAndInstall
updater.allowPrereleases                  // get/set
updater.lastCheckDate                     // read-only; last check attempt (success or failure)
```

A persisted value, once set, overrides the `SunshineConfiguration` value
passed at the next launch. `SunshineUpdateSettingsView` (see below) is a
ready-made UI for these.

## Configuration reference

`SunshineConfiguration` fields (`owner`/`repo` required, the rest optional):

| Field                 | Default                    | Purpose                                                                                                                  |
| --------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `owner`, `repo`       | (required)                 | GitHub repository to check for releases                                                                                  |
| `allowPrereleases`    | `false`                    | Consider releases marked "prerelease"                                                                                    |
| `assetMatcher`        | `.zipOrDmgContainingApp()` | How to pick an asset from a release; also accepts `.regex` or `.custom`                                                  |
| `githubToken`         | `nil`                      | Raises the API rate limit from 60/hr to 5000/hr; recommended if checking more than hourly                                |
| `checkInterval`       | `nil`                      | Seconds between automatic background checks; `nil` disables automatic checking                                           |
| `installLocation`     | `nil`                      | Overrides the install path; defaults to `Bundle.main.bundleURL`                                                          |
| `requireNotarization` | `true`                     | Also require a passing Gatekeeper/notarization check, not just a Team ID match                                           |
| `automationLevel`     | `.manual`                  | `.manual` (prompt only), `.autoDownload` (auto-download, prompt to install), or `.autoDownloadAndInstall` (fully silent) |

Automatic checks run on launch (rate-limited) and every `checkInterval`
seconds, with exponential backoff on repeated failures.

## How verification and install work

1. Check: fetch the latest (or, if prereleases are allowed, most recent
   qualifying) GitHub release, compare its tag against the running app's
   version. An update is available only if the candidate version is strictly
   newer than the running version.
2. Download: `URLSession` streams the asset to a system temporary file, which
   is then moved into a per-app cache directory:
   `~/Library/Caches/<bundleIdentifier>/Sunshine/updates/<releaseTag>/<assetName>`.
   Extraction happens in an `extracted/` folder alongside it. This directory
   is left in place after install for the caller to clean up.
3. Verify: extract the `.app`, check its code signature is valid, and check
   its Team ID matches the currently running app's Team ID (read live via
   `SecCodeCopySelf`, not from cached config). If `requireNotarization` is
   set, also check notarization/Gatekeeper acceptance. Any failure here
   rejects the update.
4. Install: clear the new bundle's quarantine flag, write a breadcrumb file
   recording the pending swap, and spawn a detached `/bin/sh` script. The app
   then terminates itself normally. `SunshineUI` uses `NSApp.terminate(nil)`,
   so the app delegate, autosave, and any unsaved-changes prompt all run;
   headless callers get `exit(0)`.
5. Swap: once the host process is gone, the script moves the old bundle
   aside, moves the new bundle into place, relaunches it, and waits for the
   sentinel file the new process writes at startup. On confirmation it
   deletes the old bundle and itself. If the relaunch is never confirmed, it
   deletes the new bundle, restores the old one, and reopens it.

Nothing on disk moves while the app is still running. The script waits for
the host process with no timeout, so a host that never exits means the update
does not happen. The script never swaps the bundle under a live process. If
termination is refused (`applicationShouldTerminate` returning
`.terminateCancel`, or a user dismissing a save prompt), call
`updater.abortPendingInstall()` to stand the script down; `install()` does
this on its own 20 seconds after asking the process to terminate.

That signal only applies while the app is alive. Once the process exits the
script proceeds regardless, so an app that takes a long time in a save dialog
and then quits still gets the update rather than silently coming back on the
old version.

Because the swap happens after this process exits, its outcome cannot be
reported through `events` or the delegate. Only failures raised before the
script is spawned surface as `.installFailed`. The script logs to
`~/Library/Caches/<bundleIdentifier>/Sunshine/relaunch.log`.

`install()` requires the install location to be writable by the current
user. There is no privileged-helper fallback: if the location isn't
writable, it returns `SunshineError.installLocationNotWritable` along with
the release's page URL for a manual download.

If the script itself dies mid-swap, the breadcrumb file lets the next launch
restore the aside'd bundle before anything else runs.

## Development

This project uses [axo](https://github.com) for task running:

```
axo build   # swift build
axo test    # swift test
axo clean   # swift package clean
```

## Example app

`Sources/SunshineExample` is a small SwiftUI app that showcases every view
`SunshineUI` provides (`SunshineUpdateSettingsView`, `UpdateAvailableView`,
`UpdateIndicatorView`, `UpdateErrorView`, and `DownloadProgressView`), picked
from a sidebar. It runs against a fixed, in-memory list of releases via
`StaticReleasesProvider` (see below), so it never hits the network.

Build and run it with [strudel](https://github.com/octavore/strudel)
(configured in `strudel.toml`):

```
strudel run
```

### Supplying releases explicitly

`StaticReleasesProvider` conforms to `ReleasesProviding` (the same protocol
`GitHubReleasesClient` uses) and serves a fixed `[GitHubRelease]` array
instead of accessing the GitHub API. Pass one to `SunshineUpdater` to run it
from known data. This is what the example app and `SunshineUI`'s
`#Preview`s use:

```swift
import SunshineCore

let releases: [GitHubRelease] = [
    GitHubRelease(tagName: "2.1.0", body: "## What's New\n\n- Faster launch times."),
]

let updater = SunshineUpdater(
    configuration: SunshineConfiguration(owner: "acme", repo: "myapp"),
    releasesProvider: StaticReleasesProvider(releases: releases)
)
```
