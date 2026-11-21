import Foundation

/// Inputs of the relaunch script, in the order the script reads its positional arguments.
/// Tests assert on this struct instead of running the script.
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
  /// Absolute paths of the two executables the script calls.
  /// The host passes them in. The script does not resolve them, so `PATH` and other
  /// inherited environment variables cannot change what runs after the host exits. Tests
  /// substitute stubs.
  var openCommand: String = "/usr/bin/open"
  var pgrepCommand: String = "/usr/bin/pgrep"
  /// Seconds to wait for the relaunched app to write its sentinel before rolling back.
  var sentinelTimeoutSeconds: Int = 10

  /// Positional script arguments.
  /// Paths are passed as arguments and are not interpolated into the script, so the shell
  /// never parses a path.
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

/// Shell script that swaps the bundle after the host process exits.
///
/// The script is embedded as a string and not shipped as an SPM resource. A resource
/// bundle adds a `Bundle.module` lookup and a copy step for every app that embeds
/// Sunshine. The script must work without build configuration.
enum RelaunchScript {
  static let source = #"""
    #!/bin/sh
    # Written and spawned by Sunshine. Waits for the host app to exit, swaps the new
    # bundle into place, relaunches it, and rolls back if the relaunch is not confirmed.
    # Every path arrives as a positional argument, so the shell never parses a path.
    set -u

    # Standard utilities (mv, rm, date, sleep, kill, touch) resolve from a fixed PATH.
    # They do not use the PATH exported by the host app. The two commands below arrive
    # as arguments for the same reason.
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
    # Absolute paths supplied by the host. They are not read from the environment. This
    # script runs after the app exits, so inherited values must not select what it runs.
    OPEN_CMD="${10}"
    PGREP_CMD="${11}"
    SENTINEL_TIMEOUT="${12}"

    log() {
        echo "[sunshine $(date '+%Y-%m-%d %H:%M:%S')] $1" >>"$LOG_PATH" 2>/dev/null
    }

    # This script runs `rm -rf` on two of these paths. Each path must be absolute, below
    # the root, and end in `.app`. The script refuses an empty, relative, or overly broad
    # path.
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

    # Wait for the host to exit. There is no timeout. Swapping the bundle under a running
    # process is worse than never updating. A host whose termination was cancelled writes
    # the abort file to release the script.
    #
    # The abort file applies only while the host is alive. After the host exits, the
    # update proceeds even if the host wrote an abort file first. A host that cancelled
    # and then quit should relaunch on the new version.
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

    # Weaker fallback for a host that builds its updater lazily and never writes the
    # sentinel. The check is whether the new bundle's executable is running. It is limited
    # to processes of this user. Otherwise `pgrep -f` matches any process whose command
    # line contains the path.
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

    # The marker remains so the next launch can finish the recovery.
    log "rollback failed; the previous bundle is still at $ASIDE_PATH"
    finish 1

    """#

  /// Write the script to `url`, replacing any copy from an earlier install.
  static func write(to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: url)
    try source.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
  }
}
