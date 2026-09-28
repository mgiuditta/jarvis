# Jarvis
Tramite macOS tra te (dettatura con Wispr Flow) e una sessione Claude Code nel vault Obsidian `~/Dev/sbu-brain`: orb olografico 3D (three.js), risposta a voce.
- Requisiti: Apple Silicon, Xcode 26+, Node (nvm), Claude Code con login (`~/.local/bin/claude`), Wispr Flow.
- Installa: `Scripts/install.sh` (test, build Release firmata con il team personale, chiude Jarvis, copia in /Applications e lo riapre).
- Usa: `⌥Space` apre il campo, detti con Wispr, dopo 3 s di testo fermo parte da solo (regolabile in Impostazioni, 0 = solo ⏎) (`⏎` subito, `Esc` annulla). Trascina un file sull'orb o sull'icona in menu bar per `/ingest`.
- Comandi: chiedi quello che vuoi, Claude sceglie la skill del vault. Jarvis gestisce solo "stop", "ripeti", "annulla" e la clipboard.
- Conferme (`⏎` sì, `Esc` no, o dettale) solo per cancellazioni, spostamenti, archivio e nuove persone o progetti.
- Voce: di sistema, "Luca (Premium)" da Accessibilità › Contenuti letti ad alta voce. Interruttore Muto nell'overlay.
- Menu › "Apri la sessione in Terminale": stessa conversazione in `claude --resume` (non usarli insieme).
- Impostazioni: hotkey, voce, colore orb (default viola), path vault/node/claude, API key opzionale (Keychain), avvio al login.
- Log: `~/Library/Logs/Jarvis/`. Sessione del giorno: `~/Library/Application Support/Jarvis/` (i vecchi modelli in `models/` si possono cancellare).
- Struttura: `Jarvis/` app Swift, `orb/` pagina three.js dell'orb, `agent/` bridge Node (JSON lines), `Scripts/` install e check.
