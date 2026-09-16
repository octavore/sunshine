import Foundation

/// Everything the relaunch script needs, in the order it reads its positional arguments.
/// Kept as a struct so tests can assert on what would be spawned without running it.
struct RelaunchPlan: Sendable, Equatable {
  let scriptURL: URL
  let hostProcessIdentifier: Int32
  let installURL: URL
  let asideURL: URL
  let stagedURL: URL
  let sentinelURL: URL
  let markerURL: URL
  let abortURL: URL
  let logURL: URL
  let releaseTag: String
  /// The two executables the script calls out to, as absolute paths. Passed in rather
  /// than resolved by the script so neither `PATH` nor any other inherited environment
  /// variable can decide what runs after the host exits. Tests substitute stubs.
  var openCommand: String = "/usr/bin/open"
  var pgrepCommand: String = "/usr/bin/pgrep"
  /// Seconds to wait for the relaunched app to write its sentinel before rolling back.
  var sentinelTimeoutSeconds: Int = 10

  /// Paths are passed as arguments rather than interpolated into the script, so nothing
  /// in a path is ever parsed by the shell.
  var arguments: [String] {
    [
      scriptURL.path,
      String(hostProcessIdentifier),
      installURL.path,
      asideURL.path,
      stagedURL.path,
      sentinelURL.path,
      markerURL.path,
      abortURL.path,
      logURL.path,
      releaseTag,
      openCommand,
      pgrepCommand,
      String(sentinelTimeoutSeconds),
    ]
  }
}

/// The shell script that performs the bundle swap after the host process has exited.
///
/// It is embedded as a string rather than shipped as an SPM resource deliberately: a
/// resource bundle would add a `Bundle.module` lookup and a copy step for every app that
/// embeds Sunshine, and this needs to work with no build configuration at all.
enum RelaunchScript {
  static let source = #"""
    #!/bin/sh
    # Written and spawned by Sunshine. Waits for the host app to exit, swaps the new
    # bundle into place, relaunches it, and rolls back if the relaunch is not confirmed.
    # Every path arrives as a positional argument, so no path is ever shell-parsed.
    set -u

    # The standard utilities below (mv, rm, date, sleep, kill, touch) are resolved from a
    # fixed PATH rather than whatever the host app happened to export, for the same reason
    # the two commands below arrive as arguments.
    PATH=/usr/bin:/bin
    export PATH

    HOST_PID="$1"
    INSTALL_PATH="$2"
    ASIDE_PATH="$3"
    STAGED_PATH="$4"
    SENTINEL_PATH="$5"
    MARKER_PATH="$6"
    ABORT_PATH="$7"
    LOG_PATH="$8"
    RELEASE_TAG="$9"
    # Absolute paths supplied by the host, never read from the environment: this script
    # runs after the app has exited, so nothing inherited should choose what it executes.
    OPEN_CMD="${10}"
    PGREP_CMD="${11}"
    SENTINEL_TIMEOUT="${12}"

    log() {
        echo "[sunshine $(date '+%Y-%m-%d %H:%M:%S')] $1" >>"$LOG_PATH" 2>/dev/null
    }

    # This script runs `rm -rf` on two of these paths, so require each one to be an
    # absolute path, below the root, ending in `.app`. An empty, relative, or overly
    # broad path is refused rather than deleted.
    for path in "$INSTALL_PATH" "$ASIDE_PATH" "$STAGED_PATH"; do
        case "$path" in
            /*/*.app) ;;
            *) log "refusing to run: '$path' is not an absolute path to a .app bundle"; exit 1 ;;
        esac
    done

    for command in "$OPEN_CMD" "$PGREP_CMD"; do
        case "$command" in
            /*) ;;
            *) log "refusing to run: '$command' is not an absolute path"; exit 1 ;;
        esac
    done

    finish() {
        rm -f "$0"
        exit "$1"
    }

    abort() {
        log "install aborted by the host; nothing was changed"
        rm -f "$ABORT_PATH" "$MARKER_PATH"
        finish 0
    }

    # Wait for the host to exit. There is no timeout ceiling on purpose: swapping the
    # bundle under a still-running process is worse than never updating. A host whose
    # termination was cancelled writes the abort file to release us.
    #
    # The abort file is only honoured while the host is alive. Once it has exited, its
    # intent to update stands, even if it wrote an abort first: a host that asked to
    # cancel and then quit anyway should come back up on the new version, not silently
    # on the old one.
    if [ "$HOST_PID" != "0" ]; then
        log "waiting for host process $HOST_PID to exit"
        while kill -0 "$HOST_PID" 2>/dev/null; do
            [ -f "$ABORT_PATH" ] && abort
            sleep 0.2
        done
    fi
    rm -f "$ABORT_PATH"

    if ! mv "$INSTALL_PATH" "$ASIDE_PATH" 2>>"$LOG_PATH"; then
        log "could not move the installed bundle aside; leaving it untouched"
        "$OPEN_CMD" -n "$INSTALL_PATH"
        rm -f "$MARKER_PATH"
        finish 1
    fi

    if ! mv "$STAGED_PATH" "$INSTALL_PATH" 2>>"$LOG_PATH"; then
        log "could not move the new bundle into place; restoring the old one"
        mv "$ASIDE_PATH" "$INSTALL_PATH" 2>>"$LOG_PATH"
        "$OPEN_CMD" -n "$INSTALL_PATH"
        rm -f "$MARKER_PATH"
        finish 1
    fi

    log "relaunching $INSTALL_PATH at $RELEASE_TAG"
    "$OPEN_CMD" -n "$INSTALL_PATH" --args "--sunshine-relaunched-from=$RELEASE_TAG"

    confirmed=0
    ticks=$((SENTINEL_TIMEOUT * 4))
    while [ "$ticks" -gt 0 ]; do
        if [ -f "$SENTINEL_PATH" ]; then
            confirmed=1
            break
        fi
        sleep 0.25
        ticks=$((ticks - 1))
    done

    # Weaker fallback for a host that builds its updater lazily and so never writes the
    # sentinel: the new bundle's executable is running. Restricted to this user's own
    # processes, since `pgrep -f` otherwise matches any process on the machine whose
    # command line happens to contain the path.
    if [ "$confirmed" -eq 0 ] && "$PGREP_CMD" -U "$(id -u)" -f "$INSTALL_PATH/Contents/MacOS/" >/dev/null 2>&1; then
        log "sentinel never appeared, but the new bundle is running"
        confirmed=1
    fi

    if [ "$confirmed" -eq 1 ]; then
        log "update to $RELEASE_TAG confirmed"
        rm -rf "$ASIDE_PATH"
        rm -f "$MARKER_PATH"
        finish 0
    fi

    log "relaunch was not confirmed; rolling back to the previous bundle"
    rm -rf "$INSTALL_PATH"
    if mv "$ASIDE_PATH" "$INSTALL_PATH" 2>>"$LOG_PATH"; then
        rm -f "$MARKER_PATH"
        "$OPEN_CMD" -n "$INSTALL_PATH"
        finish 1
    fi

    # The marker survives so the next launch can finish the recovery.
    log "rollback failed; the previous bundle is still at $ASIDE_PATH"
    finish 1

    """#

  /// Writes the script to `url`, replacing any copy left by an earlier install.
  static func write(to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: url)
    try source.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
  }
}
