import Foundation
import Testing

@testable import SupacodeSettingsShared

struct DroidSettingsInstallerTests {
  private let fileManager = FileManager.default

  private func makeTempHomeURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("supacode-droid-installer-\(UUID().uuidString)", isDirectory: true)
  }

  private func loadSettingsObject(at settingsURL: URL) throws -> [String: JSONValue] {
    let data = try Data(contentsOf: settingsURL)
    return try #require(try JSONDecoder().decode(JSONValue.self, from: data).objectValue)
  }

  @Test func settingsURLResolvesToFactoryHooks() {
    let homeURL = URL(fileURLWithPath: "/Users/test", isDirectory: true)
    let url = DroidSettingsInstaller.settingsURL(homeDirectoryURL: homeURL)
    #expect(url.path(percentEncoded: false) == "/Users/test/.factory/hooks.json")
  }

  @Test func installStateIsNotInstalledWhenFileMissing() throws {
    let homeURL = makeTempHomeURL()
    defer { try? fileManager.removeItem(at: homeURL) }

    let installer = DroidSettingsInstaller(homeDirectoryURL: homeURL, fileManager: fileManager)
    #expect(try installer.installState() == .notInstalled)
  }

  @Test func installStateThrowsWhenFileIsUnreadableAsUTF8() throws {
    let homeURL = makeTempHomeURL()
    defer { try? fileManager.removeItem(at: homeURL) }

    let settingsURL = DroidSettingsInstaller.settingsURL(homeDirectoryURL: homeURL)
    try fileManager.createDirectory(
      at: settingsURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    // Invalid UTF-8 bytes:
    try Data([0xFF, 0xFE, 0xFD, 0x00]).write(to: settingsURL)

    let installer = DroidSettingsInstaller(homeDirectoryURL: homeURL, fileManager: fileManager)
    #expect(throws: (any Error).self) { try installer.installState() }
  }

  @Test func installAllHooksWritesSupacodeManagedHooks() throws {
    let homeURL = makeTempHomeURL()
    defer { try? fileManager.removeItem(at: homeURL) }

    let installer = DroidSettingsInstaller(homeDirectoryURL: homeURL, fileManager: fileManager)
    try installer.installAllHooks()

    let settingsURL = DroidSettingsInstaller.settingsURL(homeDirectoryURL: homeURL)
    #expect(fileManager.fileExists(atPath: settingsURL.path))

    let data = try Data(contentsOf: settingsURL)
    let root = try JSONDecoder().decode(JSONValue.self, from: data)
    let hooksObject = try #require(root.objectValue)

    #expect(root.objectValue?["hooks"] == nil)
    #expect(hooksObject["SessionStart"] != nil)
    #expect(hooksObject["UserPromptSubmit"] != nil)
    #expect(hooksObject["PreToolUse"] != nil)
    #expect(hooksObject["PostToolUse"] != nil)
    #expect(hooksObject["Notification"] != nil)
    #expect(hooksObject["Stop"] != nil)
    #expect(hooksObject["SessionEnd"] != nil)

    #expect(try installer.installState() == .installed)
  }

  @Test func promptAndToolHooksReestablishPresenceBeforeBusy() throws {
    // A "new conversation" reuses the Droid process, so the old SessionEnd
    // clears presence; the next prompt or tool call must re-register it.
    let hooks = try DroidHookSettings.hooksByEvent()
    let presenceAndBusy = AgentHookSettingsCommand.compositeCommand(
      events: [.sessionStart, .busy], forwardStdinAsNotification: false, agent: .droid)
    let awaitingInput = AgentHookSettingsCommand.compositeCommand(
      events: [.awaitingInput], forwardStdinAsNotification: false, agent: .droid)

    func commands(event: String, matcher: String?) throws -> [String] {
      let groups = try #require(hooks[event])
      return groups.compactMap { group -> [String]? in
        guard group.objectValue?["matcher"]?.stringValue == matcher else { return nil }
        return group.objectValue?["hooks"]?.arrayValue?.compactMap { $0.objectValue?["command"]?.stringValue }
      }.flatMap { $0 }
    }

    #expect(try commands(event: "UserPromptSubmit", matcher: nil) == [presenceAndBusy])
    #expect(try commands(event: "PreToolUse", matcher: "") == [presenceAndBusy])
    #expect(
      try commands(event: "PreToolUse", matcher: "AskUserQuestion|ExitPlanMode") == [awaitingInput])
  }

  @Test func preFixPromptHooksReadOutdatedAndHealOnInstallKeepingUserHooks() throws {
    // Existing installs carry the busy-only prompt/tool hooks from before the
    // presence fix. They must read as outdated (which arms the once-per-session
    // auto-heal) and the heal must not drop user-authored hooks.
    let homeURL = makeTempHomeURL()
    defer { try? fileManager.removeItem(at: homeURL) }

    let installer = DroidSettingsInstaller(homeDirectoryURL: homeURL, fileManager: fileManager)
    try installer.installAllHooks()

    let settingsURL = DroidSettingsInstaller.settingsURL(homeDirectoryURL: homeURL)
    var root = try loadSettingsObject(at: settingsURL)
    let busyOnly = AgentHookSettingsCommand.compositeCommand(
      events: [.busy], forwardStdinAsNotification: false, agent: .droid)
    func group(command: String, matcher: String? = nil) -> JSONValue {
      var object: [String: JSONValue] = [
        "hooks": .array([
          .object([
            "type": "command",
            "command": .string(command),
            "timeout": .int(AgentHookSettingsCommand.timeoutSeconds),
          ])
        ])
      ]
      if let matcher { object["matcher"] = .string(matcher) }
      return .object(object)
    }
    root["UserPromptSubmit"] = .array([group(command: busyOnly)])
    root["PreToolUse"] = .array([
      group(command: busyOnly, matcher: ""),
      group(
        command: AgentHookSettingsCommand.compositeCommand(
          events: [.awaitingInput], forwardStdinAsNotification: false, agent: .droid),
        matcher: "AskUserQuestion|ExitPlanMode"),
    ])
    var postToolUse = root["PostToolUse"]?.arrayValue ?? []
    postToolUse.append(group(command: "prettier --write"))
    root["PostToolUse"] = .array(postToolUse)
    try JSONEncoder().encode(JSONValue.object(root)).write(to: settingsURL)

    #expect(try installer.installState() == .outdated)

    try installer.installAllHooks()

    #expect(try installer.installState() == .installed)
    let healed = try String(contentsOf: settingsURL, encoding: .utf8)
    #expect(healed.contains("prettier --write"))
    let presenceAndBusy = AgentHookSettingsCommand.compositeCommand(
      events: [.sessionStart, .busy], forwardStdinAsNotification: false, agent: .droid)
    let healedRoot = try loadSettingsObject(at: settingsURL)
    let promptCommands = healedRoot["UserPromptSubmit"]?.arrayValue?
      .compactMap { $0.objectValue?["hooks"]?.arrayValue }
      .flatMap { $0 }
      .compactMap { $0.objectValue?["command"]?.stringValue }
    #expect(promptCommands == [presenceAndBusy])
  }

  @Test func installStateReturnsOutdatedWhenManagedBodyDrifted() throws {
    let homeURL = makeTempHomeURL()
    defer { try? fileManager.removeItem(at: homeURL) }

    let settingsURL = DroidSettingsInstaller.settingsURL(homeDirectoryURL: homeURL)
    try fileManager.createDirectory(
      at: settingsURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    // Ownership marker present but SessionStart carries a stale busy command:
    let staleCommand = AgentHookSettingsCommand.compositeCommand(
      events: [.busy], forwardStdinAsNotification: false, agent: .droid)
    let stale: JSONValue = .object([
      "SessionStart": .array([
        .object([
          "hooks": .array([
            .object([
              "type": "command",
              "command": .string(staleCommand),
              "timeout": 5,
            ])
          ])
        ])
      ])
    ])
    try JSONEncoder().encode(stale).write(to: settingsURL)

    let installer = DroidSettingsInstaller(homeDirectoryURL: homeURL, fileManager: fileManager)
    #expect(try installer.installState() == .outdated)
  }

  @Test func uninstallRemovesManagedHooks() throws {
    let homeURL = makeTempHomeURL()
    defer { try? fileManager.removeItem(at: homeURL) }

    let installer = DroidSettingsInstaller(homeDirectoryURL: homeURL, fileManager: fileManager)
    try installer.installAllHooks()
    try installer.uninstallAllHooks()

    let settingsURL = DroidSettingsInstaller.settingsURL(homeDirectoryURL: homeURL)
    let data = try Data(contentsOf: settingsURL)
    let root = try JSONDecoder().decode(JSONValue.self, from: data)
    let hooksObject = root.objectValue ?? [:]
    #expect(hooksObject.isEmpty)
    #expect(try installer.installState() == .notInstalled)
  }

  @Test func installPreservesUserAuthoredHooksInSameFile() throws {
    let homeURL = makeTempHomeURL()
    defer { try? fileManager.removeItem(at: homeURL) }

    let settingsURL = DroidSettingsInstaller.settingsURL(homeDirectoryURL: homeURL)
    try fileManager.createDirectory(
      at: settingsURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let existing = """
      {
        "PostToolUse": [
          {
            "hooks": [
              {
                "type": "command",
                "command": "prettier --write"
              }
            ]
          }
        ]
      }
      """
    try existing.write(to: settingsURL, atomically: true, encoding: .utf8)

    let installer = DroidSettingsInstaller(homeDirectoryURL: homeURL, fileManager: fileManager)
    try installer.installAllHooks()

    let text = try String(contentsOf: settingsURL, encoding: .utf8)
    #expect(text.contains("prettier --write"))
    #expect(text.contains(AgentHookSettingsCommand.ownershipMarker))
    #expect(try installer.installState() == .installed)
  }

  @Test func uninstallPreservesUserAuthoredHooksInSameFile() throws {
    let homeURL = makeTempHomeURL()
    defer { try? fileManager.removeItem(at: homeURL) }

    let settingsURL = DroidSettingsInstaller.settingsURL(homeDirectoryURL: homeURL)
    try fileManager.createDirectory(
      at: settingsURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let existing = """
      {
        "PostToolUse": [
          {
            "hooks": [
              {
                "type": "command",
                "command": "prettier --write"
              }
            ]
          }
        ]
      }
      """
    try existing.write(to: settingsURL, atomically: true, encoding: .utf8)

    let installer = DroidSettingsInstaller(homeDirectoryURL: homeURL, fileManager: fileManager)
    try installer.installAllHooks()
    try installer.uninstallAllHooks()

    let text = try String(contentsOf: settingsURL, encoding: .utf8)
    #expect(text.contains("prettier --write"))
    #expect(!text.contains(AgentHookSettingsCommand.ownershipMarker))
    #expect(try installer.installState() == .notInstalled)
  }

  @Test func installMigratesLegacyNestedHooksWrapper() throws {
    let homeURL = makeTempHomeURL()
    defer { try? fileManager.removeItem(at: homeURL) }

    let settingsURL = DroidSettingsInstaller.settingsURL(homeDirectoryURL: homeURL)
    try fileManager.createDirectory(
      at: settingsURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let managedCommand = AgentHookSettingsCommand.compositeCommand(
      events: [.idle], forwardStdinAsNotification: false, agent: .droid)
    let legacy: JSONValue = .object([
      "hooks": .object([
        "PostToolUse": .array([
          .object([
            "hooks": .array([
              .object([
                "type": "command",
                "command": "prettier --write",
              ]),
              .object([
                "type": "command",
                "command": .string(managedCommand),
              ]),
            ])
          ])
        ])
      ])
    ])
    try JSONEncoder().encode(legacy).write(to: settingsURL)

    let installer = DroidSettingsInstaller(homeDirectoryURL: homeURL, fileManager: fileManager)
    #expect(try installer.installState() == .outdated)

    try installer.installAllHooks()

    let data = try Data(contentsOf: settingsURL)
    let root = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(root.objectValue?["hooks"] == nil)

    let text = try String(contentsOf: settingsURL, encoding: .utf8)
    #expect(text.contains("prettier --write"))
    #expect(text.contains(AgentHookSettingsCommand.ownershipMarker))
    #expect(try installer.installState() == .installed)
  }
}
