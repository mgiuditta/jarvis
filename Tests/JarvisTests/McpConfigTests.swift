import Foundation
import Testing
@testable import JarvisCore

struct McpConfigTests {
    let url = FileManager.default.temporaryDirectory.appending(path: "jarvis-tests-\(UUID().uuidString)/mcp.json")

    @Test func missingFileLoadsEmpty() {
        #expect(McpConfig.load(from: url).isEmpty)
    }

    @Test func saveKeepsFieldsTheDashboardDoesNotEdit() throws {
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let servers: [String: [String: Any]] = [
            "fs": ["type": "stdio", "command": "npx", "args": ["-y", "server-fs"], "env": ["TOKEN": "x"]],
        ]
        try McpConfig.save(servers, to: url)
        let fs = try #require(McpConfig.load(from: url)["fs"])
        #expect(fs["command"] as? String == "npx")
        #expect(fs["args"] as? [String] == ["-y", "server-fs"])
        #expect(fs["env"] as? [String: String] == ["TOKEN": "x"])
    }

    @Test func fileWithoutMcpServersLoadsEmpty() throws {
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"other": 1}"#.utf8).write(to: url)
        #expect(McpConfig.load(from: url).isEmpty)
    }
}
