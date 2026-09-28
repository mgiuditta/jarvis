# Jarvis
Tramite macOS tra te (dettatura con Wispr Flow) e una sessione Claude Code o GitHub Copilot in una cartella di lavoro (di default il vault Obsidian `~/Dev/sbu-brain`): orb olografico 3D (three.js), risposta a voce. © 2026 Matteo Giuditta, licenza MIT (`LICENSE`).
- Requisiti: Apple Silicon, Node, Wispr Flow e uno dei due motori: Claude Code con login (`~/.local/bin/claude`) oppure Copilot CLI con login GitHub (`copilot`, poi `/login`). Per compilare: Xcode 26+.
- Da passare ad altri: `Scripts/release.sh` crea `build/release/Jarvis-<versione>.dmg` firmato Developer ID e notarizzato (setup una tantum nell'intestazione dello script). Chi lo riceve trascina Jarvis in Applicazioni, poi in Impostazioni sceglie motore e cartella.
- Installa: `Scripts/install.sh` (test, build Release firmata con il team personale, chiude Jarvis, copia in /Applications e lo riapre).
- Usa: `⌥Space` apre il campo, detti con Wispr, dopo 3 s di testo fermo parte da solo (regolabile in Impostazioni, 0 = solo ⏎) (`⏎` subito, `Esc` annulla). Trascina un file sull'orb o sull'icona in menu bar per `/ingest`. Una cartella (es. un progetto in `~/Dev`) non viene copiata: il suo path assoluto finisce nel campo e detti cosa farne.
- Comandi: chiedi quello che vuoi, Claude sceglie la skill del vault. Jarvis gestisce solo "stop" (o il pulsante ■ mentre risponde), "ripeti", "annulla", `/clear` ("nuova sessione") e la clipboard.
- Conferme (`⏎` sì, `Esc` no, o dettale) solo per cancellazioni, spostamenti, archivio e nuove persone o progetti.
- Voce: di sistema, "Luca (Premium)" da Accessibilità › Contenuti letti ad alta voce. Interruttore Muto nell'overlay.
- Menu › "Apri la sessione in Terminale": stessa conversazione in `claude --resume` (non usarli insieme).
- Impostazioni: hotkey, voce, colore orb (default viola), motore (Claude/Copilot), cartella di lavoro, path node/claude/copilot, API key opzionale (Keychain), avvio al login. Fuori dal vault (niente `00-Inbox/`) spariscono le voci del vault e i file trascinati finiscono nel campo come le cartelle.
- Menu › Cruscotto MCP: stato e tool di ogni server MCP visto dal motore, riconnessione, aggiunta/rimozione dei server di Jarvis (`~/Library/Application Support/Jarvis/mcp.json`, usato da entrambi i motori), coda del log.
- Log: `~/Library/Logs/Jarvis/`. Sessione del giorno: `~/Library/Application Support/Jarvis/` (i vecchi modelli in `models/` si possono cancellare).
- Struttura: `Jarvis/` app Swift, `orb/` pagina three.js dell'orb, `agent/` bridge Node (JSON lines: `agent.mjs` Claude, `copilot.mjs` Copilot, `common.mjs` condiviso), `Scripts/` install e check.
