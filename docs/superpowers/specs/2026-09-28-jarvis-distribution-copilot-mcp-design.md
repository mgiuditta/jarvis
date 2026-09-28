# Jarvis: distribuzione, backend Copilot, cruscotto MCP

## Distribuzione e licenza
- `LICENSE` MIT, Copyright (c) 2026 Matteo Giuditta; copyright anche in Info.plist.
- Bundle id `com.matteogiuditta.jarvis`. Al primo avvio le preferenze del vecchio `com.mgiuditta.jarvis` vengono copiate.
- `Scripts/release.sh`: build Release, firma Developer ID (Hardened Runtime, timestamp) di ogni Mach-O in `Resources/agent` e dell'app, `.dmg` firmato, notarizzato (`notarytool`, profilo `jarvis`) e stapled. `install.sh` resta per l'uso personale.
- Requisiti per chi riceve: Node, e Claude Code o Copilot CLI con login.
- Cartella di lavoro qualsiasi. Se manca, l'agente non parte e chiede di sceglierla in Impostazioni.
- Le parti del vault (daily, skill, menu, `/ingest` in `00-Inbox`) si attivano solo se la cartella contiene `00-Inbox/`.

## Backend Claude / Copilot
- Impostazioni › Motore: `claude` (default) o `copilot`. Swift avvia `agent/agent.mjs` o `agent/copilot.mjs`.
- Stesso protocollo JSON-lines, codice condiviso in `agent/common.mjs`.
- `copilot.mjs` usa `@github/copilot-sdk` con la Copilot CLI dell'utente (`JARVIS_COPILOT`), sessione giornaliera riesumata come per Claude.
- Le conferme vocali passano da `policy.mjs`: `copilotQuestion` mappa shell→Bash e write→Write.

## Cruscotto MCP
- Fonte unica `~/Library/Application Support/Jarvis/mcp.json` (`{"mcpServers": {...}}`, formato `.mcp.json`), passata a entrambi i motori.
- Protocollo: in `mcp_status` | `mcp_reconnect{name}` | `mcp_reload`; out `mcp_status{servers:[{name,status,error,source,tools}]}`.
- Finestra "Cruscotto MCP" dalla menu bar: stato per server, tool, Riconnetti, aggiungi/rimuovi (stdio/http) su `mcp.json`, coda del log. I server che non vengono da Jarvis sono in sola lettura.
