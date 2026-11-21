import Foundation

/// Per-task `URLSession` delegate that reports download progress as a fraction from 0 to 1.
/// `SunshineUpdater.download(_:)` uses it so the update sheet shows a live progress bar
/// during a large download.
final class DownloadProgressForwarder: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate,
  @unchecked Sendable
{
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

  // Required by `URLSessionDownloadDelegate`. The async `download(for:delegate:)` return
  // value provides the downloaded file, so this does nothing.
  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {}
}
