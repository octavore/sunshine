import Foundation

/// Per-task `URLSession` delegate that reports download progress as a 0...1 fraction.
/// Used by `SunshineUpdater.download(_:)` so the update sheet can show a live progress bar
/// instead of appearing frozen while a multi-megabyte bundle downloads.
final class DownloadProgressForwarder: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        onProgress(fraction)
    }

    // Required by `URLSessionDownloadDelegate`; the downloaded file is consumed via the
    // async `download(for:delegate:)` return value, so nothing to do here.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}
}
