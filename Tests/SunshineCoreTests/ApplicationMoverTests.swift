import Foundation
import Testing

@testable import SunshineCore

@Suite struct ApplicationMoverTests {
  private func makeRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func makeApp(in root: URL, marker: String) throws -> URL {
    let app = root.appendingPathComponent("MyApp.app", isDirectory: true)
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    try marker.write(to: app.appendingPathComponent("marker"), atomically: true, encoding: .utf8)
    return app
  }

  @Test func copiesIntoTheFirstWritableDirectory() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let app = try makeApp(in: root.appendingPathComponent("source"), marker: "new")
    let target = root.appendingPathComponent("Applications", isDirectory: true)

    let copy = try ApplicationMover.copy(appAt: app, into: [target])

    #expect(copy.path == target.appendingPathComponent("MyApp.app").path)
    let marker = try String(contentsOf: copy.appendingPathComponent("marker"), encoding: .utf8)
    #expect(marker == "new")
    #expect(FileManager.default.fileExists(atPath: app.path))
  }

  @Test func skipsAnUnwritableDirectory() throws {
    let root = try makeRoot()
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("locked").path)
      try? FileManager.default.removeItem(at: root)
    }
    let app = try makeApp(in: root.appendingPathComponent("source"), marker: "new")
    let locked = root.appendingPathComponent("locked", isDirectory: true)
    try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555], ofItemAtPath: locked.path)
    let fallback = root.appendingPathComponent("fallback", isDirectory: true)

    let copy = try ApplicationMover.copy(appAt: app, into: [locked, fallback])

    #expect(copy.deletingLastPathComponent().lastPathComponent == "fallback")
  }

  @Test func failsIfNoDirectoryIsWritable() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let app = try makeApp(in: root.appendingPathComponent("source"), marker: "new")

    #expect(throws: (any Error).self) {
      try ApplicationMover.copy(appAt: app, into: [])
    }
  }
}
