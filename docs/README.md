# docs/ — what is generated from what

Three artifacts here are derived from others. When you edit a source, regenerate its outputs
so the copies don't drift.

## Architecture diagram

| File | Role |
|---|---|
| `architecture.excalidraw` | Original sketch (open at [excalidraw.com](https://excalidraw.com)). Kept as the editable starting point. |
| `architecture.svg` | **Canonical rendering** — hand-tuned SVG (fonts, spacing). Edit this for label/text fixes, or re-export from the `.excalidraw` and re-tune. |
| `architecture.png` | What the README embeds. **Generated** — never edit by hand. |

Regenerate the PNG after any SVG change:

```powershell
./tools/render-diagram.ps1
```

If you change diagram *content* (not just styling), update **both** `architecture.excalidraw`
and `architecture.svg` so the editable sketch stays truthful, then re-render the PNG.

## Cheat sheets (EN + CS)

| File | Role |
|---|---|
| `EA-MCP-cheatsheet-{en,cs}.md` | **Canonical content** — edit these. |
| `EA-MCP-cheatsheet-{en,cs}.html` | Hand-formatted A4 print layout of the same content. Update to match the `.md` after content changes. |
| `EA-MCP-cheatsheet-{en,cs}.pdf` | **Generated** — print the HTML to PDF (browser ▸ Print ▸ Save as PDF, A4, default margins, background graphics on). |

The EN and CS variants are translations of each other — apply content changes to both.
