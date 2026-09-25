# Jarvis come tramite Wispr ↔ Claude Code, con orb 3D viola

Data: 2026-09-25 · Stato: approvato in brainstorming

## Obiettivo
Jarvis smette di fare speech-to-text e routing. Diventa un tramite: tu detti con **Wispr Flow**, Jarvis passa il testo alla **sessione Claude Code del giorno nel vault** (`~/Dev/sbu-brain`, unica fonte di verità), mostra cosa fa Claude e legge la risposta. L'interfaccia è un orb olografico 3D viola ispirato a JARVIS (prototipo approvato: `assets/orb-prototype.html`).

## Decisioni
| Tema | Scelta |
|---|---|
| Sessione | Sessione propria via Agent SDK (come oggi), riapribile in terminale con `claude --resume <id>` |
| Input | Campo di testo nell'overlay; Wispr ci scrive; invio automatico dopo 1 s di testo fermo; `⏎` invia subito, `Esc` annulla |
| Output | Voce di sistema (Luca Premium) per la parte parlata, resto a schermo; interruttore muto |
| Orb | Prototipo three.js dentro `WKWebView`, three.js incluso nel bundle (no CDN) |

## Flusso
1. `⌥Space` → overlay visibile, **Jarvis attivato** (`NSApp.activate`) e focus sul campo. Serve attivare davvero l'app: Wispr scrive nell'app in primo piano, e l'`OverlayPanel` oggi è `.nonactivatingPanel`.
2. Detti con Wispr (fn). Ogni cambio del testo riavvia un timer di 1 s; a scadenza, se il testo non è vuoto, parte `heard(text)`.
3. `Intent.route` gestisce solo: stop, annulla, ripeti, sì/no, clipboard. Tutto il resto → `.agent(testo)`.
4. Mentre Claude lavora: orb in `thinking`, i `tool_call`/`file_changed` scorrono nel pannello HUD (esiste già come lista `tools`).
5. Risposta: la parte prima della prima riga vuota è letta da `Speaker` (voce di sistema); il testo completo resta nell'HUD. Orb in `speaking` con il livello della voce vera.
6. Conferme (`need_confirmation`): orb ambra, domanda letta; `⏎` = sì, `Esc` = no, oppure dettare "sì"/"no".
7. Menu › "Apri in Terminale": apre Terminal con `cd <vault> && claude --resume <session_id>` letto da `session.json`. La voce di menu avvisa di non usare Jarvis in contemporanea.

## Componenti
- **`Jarvis/orb/`** (nuovo, risorse bundle): `orb.html` (dal prototipo, senza UI di debug, sfondo con maschera radiale), `three.module.min.js` e gli addon `EffectComposer`, `RenderPass`, `UnrealBloomPass` (+ dipendenze) copiati da `three@0.160.0`. Espone `window.orb.set({state, level})` e `window.orb.pause(bool)`.
- **`OrbView`** (sostituisce `Orb.swift` + `Orb.metal`): `NSViewRepresentable` con `WKWebView` che carica `orb.html` via `loadFileURL`. Un timer a 30 Hz, attivo solo con overlay visibile, chiama `orb.set` con `AppState.state` e `speaker.levels.value.x`.
- **`Overlay.swift`**: aggiunge il campo di input (Wispr target) con invio automatico, l'interruttore muto e l'orb 3D al posto di quello Metal. `OverlayPanel` deve poter diventare key.
- **`AppState.swift`**: `listen()` diventa "mostra overlay + focus campo"; via tutti i riferimenti ad `audio`; `⏎`/`Esc` per le conferme.
- **`Speaker.swift`**: rimosso TTSKit; resta il percorso `AVSpeechSynthesizer.write()` → `AVAudioEngine` (serve per la FFT dell'orb). Aggiunto `muted`.
- **`Intent.swift`**: ridotto ai comandi di controllo e alla clipboard.
- **`agent.mjs`**: `STYLE` include la data e l'ora di oggi e l'indicazione di leggere la daily `00-Inbox/daily/<oggi>.md` quando serve contesto.
- **`JarvisApp.swift`**: voce di menu "Apri in Terminale".
- **`Settings.swift`**: via le voci neurali, restano quelle di sistema.

## Rimosso
- `AudioIn.swift` e il pacchetto WhisperKit
- Il pacchetto TTSKit
- `Orb.swift`, `Orb.metal`
- Lo step "modello vocale" dell'onboarding. Il permesso microfono non serve più, quindi va tolto `NSMicrophoneUsageDescription` se presente.
- I modelli scaricati in `~/Library/Application Support/Jarvis/models`: li cancella l'utente a mano, l'app non lo fa.

## Errori
| Caso | Comportamento |
|---|---|
| L'agente Node muore | Backoff e riavvio esistenti; orb in `error`; messaggio nell'HUD |
| La WebView non carica | Overlay solo testo, errore nel log; il resto funziona |
| La voce Luca non c'è | Voce italiana di default; avviso nelle Impostazioni |
| Wispr sbaglia | `Esc` prima dell'invio; "annulla" durante l'esecuzione |
| Sei in call | Muto: nessuna voce, solo HUD |

## Verifica
- `Scripts/IntentCheck.swift` aggiornato ai comandi rimasti; tra questi "sincronizza i messaggi" deve andare a Claude, non a `.unsupported`.
- Check dell'invio automatico, con una funzione pura sul debounce: testo fermo per 1 s → invio; un cambio → il timer riparte; testo vuoto → niente.
- `agent/policy.test.mjs` resta com'è.
- Prova manuale: hotkey → dettatura Wispr → risposta vocale → conferma con `⏎` → "Apri in Terminale" riprende la sessione.

## Fuori scope
- Voce neurale (si può riaggiungere se Luca non basta).
- Collegarsi a una sessione Claude Code già aperta nel terminale (opzione B, scartata).
- Skill `/pull-wispr` e pulizia del vault: sono lavori separati sul vault, non sull'app.
