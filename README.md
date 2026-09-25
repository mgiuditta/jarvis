# Jarvis
Assistente vocale macOS (menu bar + orb Metal) per il vault Obsidian `~/Dev/sbu-brain`, via Claude Agent SDK.
- Requisiti: Apple Silicon, Xcode 26+ con Metal Toolchain, Node (nvm), Claude Code con login (`~/.local/bin/claude`).
- Installa: chiudi Jarvis, poi `Scripts/install.sh` (test, build Release firmata con il team personale, copia in /Applications). Aprilo tu.
- Usa: `⌥Space` per parlare, di nuovo per finire; trascina un file sull'orb o sull'icona in menu bar per `/ingest`.
- Comandi: "prepara/chiudi la giornata", "ingesta…", "decisione: …", "sincronizza ticket/MR", "settimana", "stop", "ripeti", "annulla".
- Conferma a voce ("sì"/"no") solo per cancellazioni, spostamenti, archivio e nuove persone o progetti.
- Voce: scarica "Luca (Premium)" da Accessibilità › Contenuti letti ad alta voce, poi sceglila nelle Impostazioni.
- Impostazioni: hotkey, voce, colore orb, path vault/node/claude, API key opzionale (Keychain), avvio al login.
- Log: `~/Library/Logs/Jarvis/` (solo testo, nessun audio). Sessione del giorno: `~/Library/Application Support/Jarvis/`.
- Struttura: `Jarvis/` app Swift, `agent/` bridge Node (JSON lines), `Scripts/` install e check.
