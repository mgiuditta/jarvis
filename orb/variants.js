// Orb variants: the model picks one by name (⟦orb:name⟧). Read by orb.js (<script>) and agent/orb.mjs (the JSON between [ and ]).
// shape = SDF id in orb.js, mood = calm|spiky|jitter|shards|pulse, hue = color override or null, hint = word for the prompt.
var ORB_VARIANTS = [
  {"name": "blob", "shape": "blob", "mood": "calm", "hue": null, "hint": "neutro"},
  {"name": "spinoso", "shape": "blob", "mood": "spiky", "hue": null, "hint": "problema, tensione"},
  {"name": "tremolante", "shape": "blob", "mood": "jitter", "hue": null, "hint": "incertezza"},
  {"name": "frammentato", "shape": "blob", "mood": "shards", "hue": null, "hint": "più cose insieme"},
  {"name": "impulsi", "shape": "blob", "mood": "pulse", "hue": null, "hint": "energia"},
  {"name": "lente", "shape": "lens", "mood": "calm", "hue": null, "hint": "ricerca"},
  {"name": "globo", "shape": "globe", "mood": "calm", "hue": null, "hint": "web, browser"},
  {"name": "busta", "shape": "envelope", "mood": "calm", "hue": null, "hint": "mail"},
  {"name": "ingranaggio", "shape": "gear", "mood": "calm", "hue": null, "hint": "configurazione"},
  {"name": "terminale", "shape": "terminal", "mood": "calm", "hue": null, "hint": "comandi"},
  {"name": "matita", "shape": "pencil", "mood": "calm", "hue": null, "hint": "scrivere, modificare"},
  {"name": "documento", "shape": "document", "mood": "calm", "hue": null, "hint": "leggere file"},
  {"name": "cartella", "shape": "folder", "mood": "calm", "hue": null, "hint": "file, drive"},
  {"name": "calendario", "shape": "calendar", "mood": "calm", "hue": null, "hint": "agenda"},
  {"name": "tavolozza", "shape": "palette", "mood": "calm", "hue": null, "hint": "design"},
  {"name": "robot-retro", "shape": "robot", "mood": "calm", "hue": null, "hint": "sub-agente, automazione"},
  {"name": "persona", "shape": "person", "mood": "calm", "hue": null, "hint": "contatti, meeting"},
  {"name": "simbionte", "shape": "symbiote", "mood": "jitter", "hue": "#101018", "hint": "lavoro lungo e autonomo"}
];
