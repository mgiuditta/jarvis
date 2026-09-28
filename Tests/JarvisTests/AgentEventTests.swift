import Foundation
import Testing
@testable import JarvisCore

/// The JSON-lines contract with agent/*.mjs. A decode failure drops the event (AgentClient logs it).
struct AgentEventTests {
    private func decode(_ json: String) throws -> AgentEvent {
        try JSONDecoder().decode(AgentEvent.self, from: Data(json.utf8))
    }

    @Test func decodesMcpStatus() throws {
        let event = try decode(#"{"type":"mcp_status","servers":[{"name":"fs","status":"connected","source":"project","tools":["read","write"]},{"name":"gh","status":"failed","error":"boom","tools":[]}]}"#)
        let servers = try #require(event.servers)
        #expect(servers.map(\.name) == ["fs", "gh"])
        #expect(servers[0].tools == ["read", "write"])
        #expect(servers[1].error == "boom")
    }

    @Test func decodesCommandsWithoutArgumentHint() throws {
        let event = try decode(#"{"type":"commands","commands":[{"name":"ingest","description":"Ingest a file"}]}"#)
        #expect(event.commands == [SlashCommand(name: "ingest", description: "Ingest a file", argumentHint: nil)])
    }

    @Test func ignoresUnknownFields() throws {
        let event = try decode(#"{"type":"done","session_id":"abc","cost_usd":0.01}"#)
        #expect(event.type == "done")
        #expect(event.session_id == "abc")
    }
}
