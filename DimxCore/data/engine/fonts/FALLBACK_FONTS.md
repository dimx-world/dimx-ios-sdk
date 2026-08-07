# Fallback fonts (multi-language)

How to add scripts that the primary UI font (Inter) doesn't cover — CJK, Arabic, Thai, Indic, etc.
The fallback list feeds **both** the UI (ImGui) **and** 3D world text (SDF), so you configure it once.

## TL;DR

1. Put the `.ttf` / `.otf` in this folder (`data/data/engine/fonts/`).
2. Add one line to `imgui.fonts.fallback` in [`../engine.json`](../engine.json).
3. Rebuild the data bundle. Done — UI and 3D text both pick it up.

```jsonc
"fallback": [
    { "file": "fonts/NotoSansCJKsc-Regular.otf" },
    { "file": "fonts/NotoSansArabic-Regular.ttf" }
]
```

## How it works

- **UI text (ImGui)** — each fallback is merged into every UI font with `ImFontConfig::MergeMode`;
  glyphs rasterize on demand. Code: `core/src/ui/imgui/FontManager.cpp` → `initImguiFonts()`.
- **3D world text (SDF)** — the same files are chained after Inter in the SDF atlas. Code:
  `FontManager::initSdfAtlas()` + `core/src/render/SdfFontAtlas.cpp` (`getGlyph()` walks the chain).
- **Order matters**: the first font containing a glyph wins. List specific scripts before broad
  ones; if two fonts overlap and the wrong glyph shows, exclude ranges via `GlyphExcludeRanges`.

## Recommended files

Download from <https://notofonts.github.io> or Google Fonts. There is **no single file** that
covers all Unicode (OpenType caps at 65,535 glyphs), so pick the scripts you need:

| Scripts | File | Notes |
|---|---|---|
| CJK + Latin/Cyrillic/Greek | `NotoSansCJKsc-Regular.otf` | One big file (~10–16 MB) |
| Arabic | `NotoSansArabic-Regular.ttf` | Needs shaping — see caveats |
| Thai | `NotoSansThai-Regular.ttf` | |
| Hebrew | `NotoSansHebrew-Regular.ttf` | |
| Devanagari (Hindi/…) | `NotoSansDevanagari-Regular.ttf` | Indic is per-script (Tamil/Telugu/Bengali/… each its own file) |

## Caveats

1. **No shaping yet.** Glyphs rasterize, but there's no contextual shaping: Arabic letters won't
   join and Indic clusters won't reorder/form conjuncts. Latin/Cyrillic/Greek/CJK/Thai are fine.
   Full correctness needs HarfBuzz (a separate, larger integration — "Phase 2").
2. **SDF atlas size.** The 3D-text atlas is a fixed 1024×1024 R8 (`AtlasSize` in
   `SdfFontAtlas.cpp`). Many distinct CJK glyphs can fill it — watch for a
   `SdfFontAtlas full; dropped glyph` log. Bump `AtlasSize` or add paging if you hit it.
3. **Bundle size.** Noto CJK is large; ship only the scripts a given build needs.
4. **Baseline / size mismatch.** A fallback may sit too high/low or look too big next to Inter.
   Fix with per-source tuning (below) — only if you actually see it.

## Per-source tuning (optional, only if a fallback looks misaligned)

Not wired by default to keep the common case (just add a file) trivial. When needed:

**UI side** — in `FontManager::initImguiFonts()`, where `mergeConfig` is built, read optional
fields from the fallback entry (you'll need to keep each fallback's `Config` node alongside its
`ObjectPtr` in `mFallbackFiles`, instead of just the file):

```cpp
mergeConfig.SizePixels    = legacySize * fontNode.get<float>("scale", 1.f);
mergeConfig.GlyphOffset.y = fontNode.get<float>("offset_y", 0.f);
```

**SDF side** — `SdfFontAtlas` bakes at one size; apply a per-font vertical offset in `getGlyph()`
by adding an `offsetY` (stored per `FontEntry`) to `glyph.y0` / `glyph.y1`.

Config would then look like:

```jsonc
{ "file": "fonts/NotoSansArabic-Regular.ttf", "scale": 1.1, "offset_y": -2 }
```

## Verify

- **UI**: set any label to non-Latin text (e.g. Chinese) — it should render (Arabic unjoined).
- **3D**: a `Text2D` object with non-Latin text.
