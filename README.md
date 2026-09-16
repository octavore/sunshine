# Sunshine

Auto-update library for macOS apps distributed via GitHub Releases. Updates are verified using macOS code signing and notarization. Updates are installed only if they are signed by the same Developer ID Team as the current version.

## Requirements

- macOS 13+
- Swift tools 6.0+
- The app must be Developer ID signed and notarized, distributed outside the Mac App Store. Self-replacing the app bundle does not work under App Sandbox, and checks in a sandboxed app fail with `SunshineError.sandboxedAppUnsupported`.
- Apple Silicon and universal binaries only. Intel-only releases are ignored.
- Release assets must be a `.zip` or `.dmg` containing a single top-level `.app`.

## Installation

Add Sunshine as a Swift Package dependency:

```swift
.package(url: "https://github.com/octavore/sunshine.git", from: "0.1.0")
```

Two products are available:

- `Sunshine`: core engine plus the SwiftUI update UI. `import Sunshine` exposes both `SunshineCore` and `SunshineUI`.
- `SunshineCore`: core engine only, no SwiftUI/AppKit dependency.

## Publishing releases

### Tags

Sunshine compares the release tag against the running app's `CFBundleShortVersionString`. Tags may carry a leading `v` (`v1.4.2` and `1.4.2` are equivalent). Versions follow semantic versioning precedence:

- Dotted numeric components compare one by one, with missing trailing components treated as zero (`1.4` equals `1.4.0`).
- A prerelease tail ranks below the same version without one (`1.4.2-beta.1` < `1.4.2`). Numeric identifiers compare numerically and rank below alphanumeric ones.
- Build metadata after `+` is ignored.

An update is offered only if the tag is strictly newer than the running version. If either version fails to parse (for example a non-numeric component), no update is offered.

### Assets

Assets are filtered by architecture before anything else. Name release assets so they contain `arm64`, `apple-silicon`, or `universal`, or omit an architecture entirely if you only publish one build:

```text
MyApp-1.4.2-arm64.zip
MyApp-1.4.2-universal.dmg
```

Assets naming `x86_64`, `x86-64`, `x64`, or `intel` as a whole word are excluded. The remaining assets are passed to the configured `assetMatcher` (see [Asset matching](#asset-matching)).

## Required startup hook

Add this line as early as possible in app startup (e.g. `applicationDidFinishLaunching`), for both UI and headless integrations. It confirms a pending relaunch from a previous update:

```swift
import SunshineCore

func applicationDidFinishLaunching(_ notification: Notification) {
    SunshineUpdater.confirmSuccessfulRelaunchIfNeeded()
    // ...
}
```

If this is omitted, Sunshine falls back to checking whether the new bundle's executable is running, which is a weaker signal of relaunch success.

`SunshineUpdater`'s initializer calls this for you, so wiring it explicitly only matters if you construct the updater lazily rather than at launch.

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

`.sunshineUpdater(_:appName:appIcon:style:)` attaches the update UI. `SunshineUpdater` starts the background check loop itself when `checkInterval` is set, so checks run whether or not the modifier is attached. The modifier defaults to a modal sheet showing the app icon, version diff, rendered release notes, and Install & Relaunch / Remind Me Later / Skip This Version actions. `appName` defaults to `CFBundleName`, and `appIcon` defaults to `Image.fromMainBundle()`, which reads `CFBundleIconFile` or `CFBundleIconName` from `Bundle.main`.

"Check for Updates…" (from `CheckForUpdatesCommand`) shows a "You're up to date!" alert when there is no update. If the newest release was previously skipped or deferred, the alert says so and offers a View Update button that brings it back.

### Less obtrusive: corner indicator

Pass `style: .cornerIndicator` to replace the auto-popping sheet with a small badge pinned to the window's bottom-trailing corner. It only appears when there's something to show (an update or an error) and stays out of the way until the user opens it.

```swift
.sunshineUpdater(updaterUI, style: .cornerIndicator)
```

Tapping the badge opens the same update-review UI in a popover. The "Check for Updates…" menu command still surfaces its result via alert/sheet regardless of `style`, since it's a deliberate user action rather than a passive notification.

### Settings pane

`SunshineUpdateSettingsView` is a prebuilt "Updates" pane for a `Settings` scene. It shows app identity, Automatically Check For Updates / Install Updates Automatically toggles, a Stable/Pre-release channel picker, and a Check Now button with a last-check timestamp. When a check finds an update, the review (release notes and Install & Relaunch) appears inline in the pane:

```swift
Settings {
    SunshineUpdateSettingsView(controller: updaterUI)
}
```

Its toggles read and write live settings on `SunshineUpdater` (`isAutomaticallyCheckingForUpdates`, `automationLevel`, `allowPrereleases`), which persist to `UserDefaults` per bundle identifier and take effect immediately, with no relaunch or extra wiring required. The Install Updates Automatically toggle switches between `.manual` and `.autoDownloadAndInstall`. Pass `showChannelPicker: false` to hide the prerelease picker.

Check Now routes through `controller.refreshUpdateStatus()`, so a version the user previously skipped or deferred is resurfaced here rather than reported as "up to date". While the pane is on screen it sets `controller.suppressesUpdateSheet`, so an update it finds shows in the pane and does not also pop as a sheet from `.sunshineUpdater` on another window. The "Check for Updates…" menu command is unaffected when the pane is closed.

### Building your own UI

`SunshineUpdaterUIController` holds the published state the built-in views use, so custom views can bind to it directly. The individual views (`UpdateAvailableView`, `UpdateIndicatorView`, `UpdateErrorView`, `DownloadProgressView`) are public and can be placed anywhere. See [SunshineUI reference](#sunshineui).

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
    let downloaded = try await updater.download(update) // updater.cancelDownload() stops this
    let verified = try await updater.verify(downloaded)
    try await updater.install(verified) // stages the swap, then terminates this process
}

// Or observe progress via the event stream (single consumer, see below):
for await event in updater.events {
    switch event {
    case .downloadProgress(let fraction, _, _): print("Downloading: \(fraction)")
    case .verificationFinished(.failure(let error)): print("Verification failed: \(error)")
    default: break
    }
}
```

`SunshineUpdater` is `@MainActor` and an `ObservableObject`, so its `state` can also be observed with Combine or SwiftUI.

`checkDownloadVerifyAndInstall(silently:)` checks, downloads, and verifies. It then installs if `silently` is `true` or `automationLevel` is `.autoDownloadAndInstall`. Otherwise it stops with the state at `.readyToInstall`.

### The event stream has a single consumer

`updater.events` is one `AsyncStream` shared by every reader of the property, not a broadcast. Each event goes to exactly one waiting loop, so two `for await` loops split the events between them. Iterate it from exactly one place. Use `SunshineUpdaterDelegate` when more than one part of the app needs to observe.

The stream is live from `init`, so events emitted before anything starts iterating are buffered rather than dropped. This matters when `checkInterval` is set, because the first check can run before the host subscribes. The buffer holds the newest `SunshineUpdater.eventBufferSize` events (256) and then discards the oldest, so a consumer that stops iterating cannot grow it without bound. The stream finishes when the updater is deallocated.

### Delegate

Set `updater.delegate` to an object conforming to `SunshineUpdaterDelegate`. The updater holds it weakly and calls it directly, independently of `events`:

| Method                           | Called when                                                                                                               |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `updater(_:didFindUpdate:)`      | A check finds an update that is not skipped or deferred                                                                   |
| `updater(_:didFailWithError:)`   | A check, download, verification, or install fails, or a pending install is aborted. A cancelled download is not reported. |
| `updaterDidFinishInstalling(_:)` | The relaunch script has been spawned, immediately before the process terminates                                           |

### Cancelling a download

`updater.cancelDownload()` stops a download in flight. `download(_:)` then throws `SunshineError.cancelled` and the state returns to `.updateAvailable`, so the user can start it again. `isDownloadCancellable` reports whether a download is running. Verification and install are deliberately not cancellable: both are short, and abandoning a bundle swap partway is worse than finishing it. The built-in sheet shows a Cancel button for the download phase only, wired to `controller.cancelDownloadTapped()`.

### Skip and remind later

`updater.skip(update)` records the update's tag as skipped. `updater.remindLater(update, for:)` defers that update for the given interval (24 hours by default). A check treats a skipped or deferred release as up to date and returns `.noUpdateAvailable(latestKnown: update, ...)` with the suppressed update, so a UI can offer it anyway. A deferral covers only the version it was used on, so a release published during the deferral is still offered.

`updater.clearSkippedVersion()` clears both the skip and any deferral. `skippedVersion`, `isRemindingLater`, and `remindLaterVersion` expose the current state read-only.

### Live settings

`SunshineUpdater` exposes three settings from `SunshineConfiguration` as mutable properties, so they can be changed at runtime (e.g. from a settings UI) instead of only at construction. Each setter persists the new value to `UserDefaults`, scoped per bundle identifier, and takes effect immediately:

```swift
updater.isAutomaticallyCheckingForUpdates // get/set; starts/stops the background loop
updater.automationLevel                   // get/set: .manual / .autoDownload / .autoDownloadAndInstall
updater.allowPrereleases                  // get/set
updater.lastCheckDate                     // read-only; last check attempt (success or failure)
updater.releasesPageURL                   // read-only; https://github.com/<owner>/<repo>/releases
```

A persisted value, once set, overrides the `SunshineConfiguration` value passed at the next launch. Turning automatic checks on when `checkInterval` is `nil` uses an interval of one hour. `SunshineUpdateSettingsView` is a ready-made UI for these.

### Supplying releases explicitly

`StaticReleasesProvider` conforms to `ReleasesProviding` (the same protocol `GitHubReleasesClient` uses) and serves a fixed `[GitHubRelease]` array instead of accessing the GitHub API. Pass one to `SunshineUpdater` to run it from known data. The example app and `SunshineUI`'s `#Preview`s use it:

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

## Configuration reference

`SunshineConfiguration` fields (`owner`/`repo` required, the rest optional):

| Field                 | Default                    | Purpose                                                                                                                  |
| --------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `owner`, `repo`       | (required)                 | GitHub repository to check for releases                                                                                  |
| `allowPrereleases`    | `false`                    | Consider releases marked "prerelease"                                                                                    |
| `assetMatcher`        | `.zipOrDmgContainingApp()` | How to pick an asset from a release (see [Asset matching](#asset-matching))                                              |
| `githubToken`         | `nil`                      | Raises the API rate limit from 60/hr to 5000/hr; recommended if checking more than hourly                                |
| `checkInterval`       | `nil`                      | Seconds between automatic background checks; `nil` disables automatic checking                                           |
| `installLocation`     | `nil`                      | Overrides the install path; defaults to `Bundle.main.bundleURL`                                                          |
| `requireNotarization` | `true`                     | Also require a passing Gatekeeper/notarization check, not just a Team ID match                                           |
| `automationLevel`     | `.manual`                  | `.manual` (prompt only), `.autoDownload` (auto-download, prompt to install), or `.autoDownloadAndInstall` (fully silent) |

### Automatic checks

When `checkInterval` is set, `SunshineUpdater.init` starts a background loop. It checks immediately if no check has been recorded or `checkInterval` has elapsed since the last one, and otherwise waits for the remainder. After a failed check the wait becomes `checkInterval`, then doubles on each further failure, up to 16 times `checkInterval`. A successful check resets it. When a check finds an update and `automationLevel` is not `.manual`, the loop downloads and verifies it without checking again. It installs only when `automationLevel` is `.autoDownloadAndInstall`. Under `.autoDownload`, `SunshineUI` then shows the review, and Install & Relaunch installs the already-verified update without downloading it again.

### Release selection

With `allowPrereleases` off, a check fetches GitHub's "latest release", which excludes drafts and prereleases. With it on, a check fetches the 10 most recent releases, drops drafts, and takes the most recently published one. When an update is found, Sunshine also fetches the recent releases, so the notes of every version newer than the running one appear together, newest first.

### Asset matching

`AssetMatching` is applied after the architecture filter:

| Case                                  | Selects                                                                                                                                                             |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.zipOrDmgContainingApp(bundleName:)` | The first `.zip` or `.dmg` asset whose name contains `bundleName` (case-insensitive; defaults to the running app's `CFBundleName`), else the first `.zip` or `.dmg` |
| `.regex(String)`                      | The first asset whose name matches the pattern. An invalid pattern matches nothing.                                                                                 |
| `.custom((GitHubAsset) -> Bool)`      | The first asset for which the closure returns `true`                                                                                                                |

If nothing matches, the check fails with `SunshineError.noMatchingAsset`. `AssetMatcher.select(from:matching:bundleName:)` runs the same selection directly.

## API reference

### SunshineCore

#### `SunshineUpdater`

| Member                                                                     | Description                                                                                                                                                                                                                                     |
| -------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `init(configuration:releasesProvider:)`                                    | Creates the updater. `releasesProvider` defaults to `GitHubReleasesClient` using `githubToken`. Also confirms a pending relaunch, recovers an interrupted install, removes stale bundles left by earlier installs, and starts automatic checks. |
| `state: UpdateState`                                                       | Current state, `@Published`                                                                                                                                                                                                                     |
| `events: AsyncStream<UpdateEvent>`                                         | Single-consumer event stream                                                                                                                                                                                                                    |
| `static eventBufferSize`                                                   | Number of unconsumed events buffered (256)                                                                                                                                                                                                      |
| `delegate: SunshineUpdaterDelegate?`                                       | Weak delegate                                                                                                                                                                                                                                   |
| `terminate: @MainActor () -> Void`                                         | How the process ends after the relaunch script starts. Defaults to `exit(0)`. `SunshineUpdaterUIController` sets it to `NSApp.terminate(nil)`.                                                                                                  |
| `checkForUpdates() async -> UpdateCheckResult`                             | Runs one check                                                                                                                                                                                                                                  |
| `download(_:) async throws -> DownloadedUpdate`                            | Downloads the update's asset                                                                                                                                                                                                                    |
| `cancelDownload()`, `isDownloadCancellable`                                | Cancels an in-flight download                                                                                                                                                                                                                   |
| `verify(_:) async throws -> VerifiedUpdate`                                | Extracts and verifies the downloaded app                                                                                                                                                                                                        |
| `verifiedUpdate: VerifiedUpdate?`                                          | The update most recently verified, for passing to `install(_:)` without downloading again                                                                                                                                                       |
| `install(_:) async throws`                                                 | Stages the swap and terminates the process                                                                                                                                                                                                      |
| `abortPendingInstall()`                                                    | Stands down a spawned relaunch script if termination was refused                                                                                                                                                                                |
| `checkDownloadVerifyAndInstall(silently:) async throws`                    | Runs the whole pipeline                                                                                                                                                                                                                         |
| `skip(_:)`, `remindLater(_:for:)`, `clearSkippedVersion()`                 | Records or clears a skip or deferral                                                                                                                                                                                                            |
| `skippedVersion`, `isRemindingLater`, `remindLaterVersion`                 | Read-only skip and deferral state                                                                                                                                                                                                               |
| `isAutomaticallyCheckingForUpdates`, `automationLevel`, `allowPrereleases` | Persisted live settings                                                                                                                                                                                                                         |
| `lastCheckDate`, `releasesPageURL`                                         | Read-only check date and releases page                                                                                                                                                                                                          |
| `static confirmSuccessfulRelaunchIfNeeded()`                               | Startup hook                                                                                                                                                                                                                                    |

#### `UpdateState`

`.idle`, `.checking`, `.updateAvailable(Update)`, `.downloading(Update, fractionComplete:)`, `.verifying(Update)`, `.readyToInstall(Update)`, `.installing`, `.upToDate`, `.error(SunshineError)`.

#### `UpdateCheckResult`

| Case                                          | Meaning                                                                                                                                                                       |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.updateAvailable(Update)`                    | A newer release with a matching asset                                                                                                                                         |
| `.noUpdateAvailable(latestKnown:releaseURL:)` | Up to date. `latestKnown` is the newer update when it was suppressed by a skip or deferral, otherwise `nil`. `releaseURL` is the release page of the release checked against. |
| `.failed(SunshineError)`                      | The check failed                                                                                                                                                              |

#### `UpdateEvent`

| Case                                                               | Emitted when                                                               |
| ------------------------------------------------------------------ | -------------------------------------------------------------------------- |
| `.checkStarted`                                                    | A check begins                                                             |
| `.checkFinished(UpdateCheckResult)`                                | A check ends                                                               |
| `.downloadProgress(fractionComplete:bytesWritten:bytesTotal:)`     | Download progress changes                                                  |
| `.verificationStarted`                                             | Verification begins                                                        |
| `.verificationFinished(Result<VerificationReport, SunshineError>)` | Verification ends                                                          |
| `.installStarted`                                                  | `install(_:)` begins                                                       |
| `.willRelaunch`                                                    | The relaunch script is waiting and the process is about to terminate       |
| `.installFailed(SunshineError)`                                    | Install failed before the swap, or was aborted. Nothing on disk was moved. |

#### `SunshineError`

| Case                                       | Raised when                                                     |
| ------------------------------------------ | --------------------------------------------------------------- |
| `.network(underlying:)`                    | A GitHub API request fails or returns a non-2xx status          |
| `.invalidRepository(owner:repo:)`          | `owner` or `repo` cannot form a valid API URL                   |
| `.rateLimited(resetAt:)`                   | The GitHub API rate limit is exhausted                          |
| `.noMatchingAsset`                         | No asset passes the architecture filter and `assetMatcher`      |
| `.downloadFailed(underlying:)`             | The asset download fails                                        |
| `.extractionFailed(underlying:)`           | The archive cannot be extracted or contains no top-level `.app` |
| `.verificationFailed(VerificationFailure)` | Signature, Team ID, or notarization verification fails          |
| `.installLocationNotWritable(URL)`         | The install location or its parent directory is not writable    |
| `.sandboxedAppUnsupported`                 | The app runs under App Sandbox                                  |
| `.relaunchFailed(underlying:)`             | The relaunch script cannot be spawned                           |
| `.cancelled`                               | A download is cancelled or a pending install is aborted         |

`VerificationFailure` cases: `.signatureInvalid(message:)`, `.teamIdentifierMismatch(expected:found:)`, `.teamIdentifierMissing`, `.notarizationRejected(reason:)`, `.runningAppUnsigned`. Both error types conform to `CustomStringConvertible` with user-readable descriptions.

#### Models

| Type                 | Fields                                                                                                                                                                                           |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Update`             | `id` (release tag), `version: AppVersion`, `releaseNotesMarkdown`, `publishedAt`, `htmlURL`, `asset: GitHubAsset`, `isPrerelease`. `init(release:asset:)`.                                       |
| `DownloadedUpdate`   | `update`, `archiveURL`, `tempDirectory`                                                                                                                                                          |
| `VerifiedUpdate`     | `update`, `extractedAppURL`, `tempDirectory`, `verificationReport`                                                                                                                               |
| `VerificationReport` | `signatureValid`, `teamIdentifier`, `runningAppTeamIdentifier`, `teamIdentifierMatches`, `notarizationAccepted` (`nil` when notarization was not required), `details`                            |
| `GitHubRelease`      | `tagName`, `name`, `body`, `draft`, `prerelease`, `publishedAt`, `htmlURL`, `assets`. `Decodable` from the GitHub API, with a memberwise `init` whose fields other than `tagName` have defaults. |
| `GitHubAsset`        | `name`, `browserDownloadURL`, `size`, `contentType`. `Decodable`, with a memberwise `init`.                                                                                                      |

#### `AppVersion`

`Comparable` version with `shortVersion` and optional `buildVersion`, following the rules in [Tags](#tags). When short versions are equal, numeric build versions break the tie.

- `init(shortVersion:buildVersion:)`
- `init(tag:)` strips a leading `v` or `V`
- `static fromMainBundle()` reads `CFBundleShortVersionString` and `CFBundleVersion`
- `isUpdate(_ candidate:)` returns `true` only when both versions parse and `candidate` is strictly newer

#### Releases

- `ReleasesProviding`: protocol with `fetchLatestRelease(owner:repo:)` and `fetchRecentReleases(owner:repo:)`.
- `GitHubReleasesClient(session:token:)`: the GitHub REST API implementation. `session` defaults to an ephemeral `URLSession`. `fetchRecentReleases(owner:repo:perPage:)` takes a page size (default 10).
- `StaticReleasesProvider(releases:)`: serves a fixed array. `fetchLatestRelease` returns the first non-draft, non-prerelease entry in array order and throws `.network` if there is none.

#### Verification and install helpers

- `UpdateVerifier(requireNotarization:checker:)` with `verify(appAt:) throws -> VerificationReport`. Every check fails closed.
- `CodeSigningChecking`: protocol with `validateSignature(at:)`, `teamIdentifierOfRunningApp()`, and `isNotarized(at:)`, for substituting canned results in tests.
- `SystemCodeSigningChecker`: the Security.framework and `spctl` implementation.
- `InstallLocationChecker.isWritable(_:)` returns `true` if both the bundle and its parent directory are writable.

### SunshineUI

#### `SunshineUpdaterUIController`

`@MainActor ObservableObject` that drives the built-in views. `init(updater:)` subscribes to `updater.state` and sets `updater.terminate` to `NSApp.terminate(nil)`.

| Member                                                             | Description                                                                                               |
| ------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| `updater`                                                          | The wrapped `SunshineUpdater`                                                                             |
| `pendingUpdate`                                                    | The update under review                                                                                   |
| `errorMessage`                                                     | Description of the last error                                                                             |
| `isPresentingUpdateSheet`                                          | Whether the update or error sheet is shown                                                                |
| `isPresentingUpToDateAlert`, `upToDateReleaseURL`, `skippedUpdate` | State for the "up to date" alert. `skippedUpdate` is set when the newest release was skipped or deferred. |
| `isInstalling`, `isDownloading`, `progress`, `statusText`          | Progress state from Install & Relaunch until the process exits                                            |
| `updateUIStyle`                                                    | Set by `.sunshineUpdater(style:)`. The sheet opens automatically only for `.sheet`.                       |
| `suppressesUpdateSheet`                                            | While `true`, found updates and errors populate state without opening the sheet                           |
| `checkForUpdatesButtonTapped()`                                    | Runs a check and shows the sheet or the "up to date" alert                                                |
| `refreshUpdateStatus() async -> UpdateCheckResult`                 | Runs a check without presenting anything, and surfaces a skipped or deferred update as `pendingUpdate`    |
| `viewSkippedUpdateTapped()`                                        | Clears the skip and shows `skippedUpdate` in the sheet                                                    |
| `installTapped()`                                                  | Downloads, verifies, and installs `pendingUpdate`                                                         |
| `cancelDownloadTapped()`                                           | Cancels the download                                                                                      |
| `remindLaterTapped()`, `skipTapped()`                              | Defers or skips `pendingUpdate` and dismisses the sheet                                                   |

#### Views and modifiers

| API                                                                         | Description                                                       |
| --------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| `View.sunshineUpdater(_:appName:appIcon:style:)`                            | Attaches the sheet or corner indicator and the "up to date" alert |
| `SunshineUpdateUIStyle`                                                     | `.sheet` or `.cornerIndicator`                                    |
| `CheckForUpdatesCommand(_:)`                                                | Adds "Check for Updates…" after the About item in the app menu    |
| `SunshineUpdateSettingsView(controller:appName:appIcon:showChannelPicker:)` | Settings pane                                                     |
| `UpdateAvailableView(controller:appName:appIcon:)`                          | Update review with release notes, actions, and install progress   |
| `UpdateIndicatorView(controller:appName:appIcon:)`                          | Corner badge that opens the review in a popover                   |
| `UpdateErrorView(message:releaseURL:)`                                      | Error message with an optional manual download link               |
| `DownloadProgressView(fractionComplete:onCancel:)`                          | Standalone progress bar with an optional Cancel button            |
| `Image.fromMainBundle()`                                                    | The running app's icon, or `nil`                                  |

## How verification and install work

1. Check: fetch the candidate release (see [Release selection](#release-selection)) and compare its tag against the running app's version. An update is available only if the candidate version is strictly newer than the running version.
2. Download: `URLSession` streams the asset to a system temporary file, which is then moved into a per-app cache directory: `~/Library/Caches/<bundleIdentifier>/Sunshine/updates/<releaseTag>/<assetName>`. Extraction happens in an `extracted/` folder alongside it. This directory is left in place after install.
3. Verify: extract the `.app`, check its code signature is valid, and check its Team ID matches the currently running app's Team ID (read live via `SecCodeCopySelf`, not from cached config). If `requireNotarization` is set, also check notarization/Gatekeeper acceptance. Any failure here rejects the update.
4. Install: check the install location is writable, verify the bundle again, clear its quarantine flag, write a breadcrumb file recording the pending swap, and spawn a detached `/bin/sh` script. The app then terminates itself through `updater.terminate`. `SunshineUI` uses `NSApp.terminate(nil)`, so the app delegate, autosave, and any unsaved-changes prompt all run; headless callers get `exit(0)`.
5. Swap: once the host process is gone, the script moves the old bundle aside, moves the new bundle into place, relaunches it, and waits for the sentinel file the new process writes at startup. On confirmation it deletes the old bundle and itself. If the relaunch is never confirmed, it deletes the new bundle, restores the old one, and reopens it.

Nothing on disk moves while the app is still running. The script waits for the host process with no timeout, so a host that never exits means the update does not happen. The script never swaps the bundle under a live process. If termination is refused (`applicationShouldTerminate` returning `.terminateCancel`, or a user dismissing a save prompt), call `updater.abortPendingInstall()` to stand the script down; `install()` does this on its own 20 seconds after asking the process to terminate.

That signal only applies while the app is alive. Once the process exits the script proceeds regardless, so an app that takes a long time in a save dialog and then quits still gets the update rather than silently coming back on the old version.

Because the swap happens after this process exits, its outcome cannot be reported through `events` or the delegate. Only failures raised before the script is spawned surface as `.installFailed`. The script logs to `~/Library/Caches/<bundleIdentifier>/Sunshine/relaunch.log`.

`install()` requires the install location to be writable by the current user. There is no privileged-helper fallback: if the location isn't writable, `install()` throws `SunshineError.installLocationNotWritable`. The built-in error view links to the release page for a manual download.

If the script itself dies mid-swap, the breadcrumb file lets the next `SunshineUpdater` initialization restore the old bundle. Initialization also deletes old bundles left aside by an interrupted install once they are more than 24 hours old.

## Example app

`Examples/SunshineExample` is a separate package containing a small SwiftUI app that showcases every view `SunshineUI` provides (`SunshineUpdateSettingsView`, `UpdateAvailableView`, `UpdateIndicatorView`, `UpdateErrorView`, and `DownloadProgressView`), picked from a sidebar. It runs against a fixed, in-memory list of releases via `StaticReleasesProvider`, so it never hits the network.

Build and run it with [strudel](https://github.com/octavore/strudel) (configured in `Examples/SunshineExample/strudel.toml`):

```text
cd Examples/SunshineExample
strudel run
```

## Development

This project uses axo for task running:

```text
axo build   # swift build
axo test    # swift test
axo clean   # swift package clean
axo example # swift run the example app
axo fmt     # swift format
```
