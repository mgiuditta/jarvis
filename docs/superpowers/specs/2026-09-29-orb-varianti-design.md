# Orb a varianti: il blob prende la forma dell'azione

## Obiettivo

Mentre Jarvis lavora, l'orb si trasforma in uno di ~140 oggetti/personaggi predefiniti scelti dall'AI
(lente per cercare, busta per la mail, simbionte nero per un lavoro lungo…) e torna blob a fine turno.
Prototipo visivo: `docs/superpowers/specs/assets/orb-varianti-prototype.html`.

## Decisioni

- **Chi sceglie:** il modello principale, con un tag nel testo `⟦orb:nome⟧` all'inizio, prima di ogni strumento e prima della risposta finale (varianti diverse a ogni passo).
  Niente chiamate extra, funziona uguale su Claude Agent SDK e Copilot.
- **Fallback deterministico:** a ogni `tool_call` noto, se il modello non ha emesso un tag negli ultimi 0,8 s, la variante arriva da una mappa fissa tool → variante.
- **Rendering:** solo il blob passa da mesh displaced a quad raymarched SDF. Alone, polvere, anelli voce, colori e stati restano come oggi.
  La variante `blob` riproduce il look attuale: a riposo l'orb non cambia.
- **Personaggi:** omaggi riconoscibili, non copie di IP (niente Pikachu/Mario/Venom esatti): l'app è distribuita firmata.
- **Priorità:** `confirm` ed `error` vincono sempre sulla variante (colore/animazione d'avviso restano riconoscibili).

## Flusso

```
prompt → agent (style() con catalogo nomi)
       → partial_text "…⟦orb:lente⟧Cerco…"
common.mjs: stripOrbTags (streaming) → partial_text senza tag + {type:'orb', variant:'lente'}
          + tool_call senza tag recente → {type:'orb', variant: TOOL_MAP[name]}
AppState.handle("orb") → orbVariant (reset a "blob" su done/error/stop/clear)
OrbWebView.push() → orb.set({..., variant})
orb.js → coda (max 3, `blob` la svuota) → morph blob → forma (passando sempre dal blob), tenuta minima 1,2 s
fine turno ok → `spunta` per ~2 s, poi `blob`
```

## Componenti

### `orb/variants.js` — fonte unica del catalogo
`var ORB_VARIANTS = [ … ]` con righe JSON `{ "name": "lente", "shape": "lens", "mood": "calm", "hue": null, "hint": "ricerca" }`.
- `name`: quello che scrive il modello (italiano, kebab-case, unico).
- `shape`: id della forma SDF (`orb/shapes*.js`; più nomi possono condividere una forma).
- `mood`: modificatore di animazione (`calm`, `spiky`, `jitter`, `shards`, `pulse`).
- `hue`: colore che sostituisce quello utente mentre la variante è attiva; `null` = colore utente.
- `hint`: parole per il prompt quando il nome non basta.

Letto da:
- **orb.html** con un `<script>` (niente `fetch` su `file://`).
- **Sidecar**: `agent/orb.mjs` legge `../orb/variants.js` relativo a sé (repo e bundle hanno `agent/` e `orb/` affiancati) e fa il parse del JSON dopo `= [`. Se manca, niente istruzioni orb e niente eventi: l'app funziona come prima.

Le forme stanno in `orb/shapes.js` (base) e `orb/shapes-*.js` (batch), ognuna come corpo GLSL `{ id: \`…\` }`.

### `agent/common.mjs`
- `style()` aggiunge `orbPrompt()` (in `agent/orb.mjs`), se il catalogo c'è: *"Prima della risposta e quando cambi fase scrivi ⟦orb:nome⟧ (invisibile all'utente). Nomi: lente, busta, …"* (solo nomi, con hint tra parentesi dove presente; ~300 token).
- `orbFilter()`: filtro con stato per i delta in streaming. Trattiene il testo da `⟦` fino a `⟧` (o fino a 40 caratteri, poi lo rilascia così com'è: non era un tag). Nome sconosciuto → scartato in silenzio. Applicato anche al `text` finale di `done`.
- `TOOL_MAP`: nome tool (match per prefisso/regex, include `mcp__…`) → variante. Esempi: WebSearch/WebFetch → `lente`, Gmail → `busta`, Calendar → `calendario`, Edit/Write → `matita`, Bash → `terminale`, Read/Glob/Grep → `documento`, claude-in-chrome → `globo`, Task/Agent → `robot-retro`.
- `agent.mjs` e `copilot.mjs` passano i delta dal filtro e chiamano il fallback su `tool_call`; nessun'altra logica duplicata.

### Swift
- `AgentEvent`: nuovo campo `variant: String?`.
- `AppState`: `var orbVariant = "blob"`; `case "orb"` lo imposta; `done`, `error`, stop, `/clear` lo riportano a `"blob"`.
- `OrbView`/`OrbWebView`: nuovo campo `variant`, aggiunto al JSON di `push()`.
- Il bundle copia già tutta `orb/` (build phase rsync): nessuna modifica al progetto Xcode.

### `orb/orb.js`
- Il blob mesh diventa un quad a schermo intero con fragment shader raymarched (come il prototipo), stesso shading: fresnel, rim, sheen iridescente, spec.
- Uniform `uShapeA`, `uShapeB`, `uMix` (morph tra due forme passando dal blob), `uMood`, più gli uniform esistenti (amp, freq, glow, level, low/high, hover).
- `map(p)` = `switch` sull'id forma → funzioni SDF. Un solo programma compilato.
- Le uniform di stato esistenti (`STATES`) continuano a pilotare wobble, glow, pulse e voce sopra qualunque forma.
- Forme sconosciute o `variant` assente → `blob`.
- Budget: ≤ 96 passi di marcia; la tela resta piccola (96–200 px), il costo GPU è trascurabile. Se una forma è troppo cara, si semplifica la sua SDF, non il marcher.

### `orb/gallery.html` (dev)
Griglia di tutte le varianti del catalogo, ognuna in morph ciclico blob → forma. Serve per QA visiva e per aggiungere forme. Mostra la forma già formata (`#demo=nome`, `&morph` per il ciclo); `#shapes=a,b` per provare forme non ancora a catalogo.

## Catalogo iniziale (102)

**Umori (5, forma `blob`):** blob (calm), spinoso (errore/tensione), tremolante (ascolto/incertezza), frammentato (più cose in parallelo), impulsi (energia).

**Oggetti (67):**
- Ricerca/web: lente, globo, bussola, binocolo, radar
- Comunicazione: busta, fumetto, telefono, megafono, aereo-carta
- Codice: ingranaggio, terminale, graffe, chiave-inglese, insetto, razzo, ramo-git
- File/documenti: cartella, documento, libro, matita, graffetta, cestino, scatola
- Tempo: calendario, orologio, clessidra, sveglia
- Dati/soldi: grafico, moneta, carrello, salvadanaio, calcolatrice
- Media: nota-musicale, cuffie, fotocamera, pellicola, microfono, tavolozza
- Meteo/natura: sole, nuvola, pioggia, fulmine, fiocco-neve, luna, fiamma, foglia, goccia
- Vita/varie: casa, lampadina, tazza-caffe, chiave, lucchetto, campanella, regalo, cuore, stella, bandiera, puntina-mappa, auto, trofeo, dado, puzzle, cervello, occhio, pollice-su, spunta

**Personaggi (30, omaggi):** persona, simbionte (nero lucido, occhi bianchi, tentacoli), idraulico-baffi, fantasmino-arcade, mangia-pallini, invasore-pixel, astronauta-fagiolo, robot-retro, supereroe-mantello, cavaliere, ninja, mago, zombie, pirata, vampiro, alieno, scheletro, detective, cowboy, gatto, cane, gufo, drago, dinosauro, polpo, pinguino, unicorno, slime, fungo-bonus, blocco-bonus.

Criterio per ogni forma: la sagoma deve leggersi a 96 px. Se non si legge, la si semplifica o si toglie dal catalogo.

**Sviluppo e design (36, omaggi, non loghi esatti):**
- Loghi dev: gatto-polpo (GitHub), volpe-tanuki (GitLab), balena-container (Docker), atomo (React), rondine (Swift), serpenti (Python), timone (Kubernetes), gopher (Go), elefante (Postgres), scudo-a (Angular), cubo-pacchetti (npm)
- Oggetti dev: database, server, chip, spina-api, pull-request, provetta, semaforo, pergamena, refresh, cancelletto
- Design: pillole-figma, diamante (Sketch), pennino-bezier, righello, squadra, livelli, griglia, contagocce, secchiello, nodi-vettore, cursore, finestra-browser, mockup-telefono, font-aa, componente

Forme in `orb/shapes-dev-1.js`, `orb/shapes-dev-2.js`, `orb/shapes-design.js`. `orb.html#demo=blob&seq=a,b,c` prova la coda.

## Posizione dell'orb

Griglia 3×3 dello schermo (`OrbZone` in `Support.swift`): angoli, centri dei bordi, centro. Al rilascio del trascinamento
l'orb scatta alla zona del terzo di schermo in cui cade; la zona è salvata in `Prefs.orbZone` (default in basso a destra).
Menu contestuale → "Posizione orb". La card si apre sotto l'orb, tranne sulla riga in basso; nella colonna centrale resta centrata.

## Consegna a fasi

1. **Pipeline** (tag, filtro, fallback, evento, Swift, uniform `variant`) con il raymarcher e 5 forme (blob, lente, busta, ingranaggio, simbionte). A questo punto funziona end-to-end.
2. **Oggetti**: le restanti forme a blocchi di categoria, validate in `gallery.html`.
3. **Personaggi**: i 30 omaggi, validati in `gallery.html`.

## Test

- `agent/orbtags.test.mjs` (stile `policy.test.mjs`): tag intero in un delta; tag spezzato su 2–3 delta; nome sconosciuto scartato; `⟦` senza chiusura rilasciato dopo 40 caratteri; testo senza tag invariato; fallback tool rispetta la finestra di 2 s.
- QA visiva: `gallery.html`, ogni variante leggibile a 96 px e a 200 px.
- Nessun lancio dell'app o reinstall senza ok esplicito (regola di progetto).

## Fuori scope

- Varianti generate dinamicamente dall'AI (solo catalogo predefinito).
- Suoni associati alle forme.
- Scelta manuale della variante da parte dell'utente.
