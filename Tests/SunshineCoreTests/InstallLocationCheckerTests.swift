import Foundation
import Testing

@testable import SunshineCore

@Suite struct InstallLocationCheckerTests {
  @Test func translocatedPathIsReported() {
    let url = URL(
      fileURLWithPath: "/private/var/folders/ab/xyz/T/AppTranslocation/1234/d/MyApp.app")
    #expect(InstallLocationChecker.issue(for: url) == .translocated)
  }

  @Test func ordinaryLocationHasNoIssue() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let app = root.appendingPathComponent("MyApp.app", isDirectory: true)
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(InstallLocationChecker.issue(for: app) == nil)
  }

  @Test func unsuitableLocationDescriptionsDifferByIssue() {
    let url = URL(fileURLWithPath: "/Volumes/Disk/MyApp.app")
    let translocated = SunshineError.installLocationUnsuitable(url, .translocated).description
    let readOnly = SunshineError.installLocationUnsuitable(url, .readOnlyVolume).description
    #expect(translocated != readOnly)
    #expect(readOnly.contains("read-only volume"))
  }
}
