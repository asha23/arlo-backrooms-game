# Store art

Drawn rather than screenshotted. A Roblox capture at this stage would show
untextured blocks, and store art has to read at roughly 150px wide in a search
result — so these are built as a one-point perspective corridor using the
level's own palette, which keeps them honest about what the game looks like
without being a photograph of placeholder geometry.

The title appears on every piece, anchored to the bottom so the corridor and
the entities stay visible behind it.

| File | Size | Where it goes |
| --- | --- | --- |
| `store-primary-1920x1080.png` | 1920×1080 | **Primary thumbnail.** Creator Dashboard → your experience → Thumbnails → upload first. Roblox shows the first thumbnail in search and on the game page header. |
| `thumbnail-1-primary.png` | 1920×1080 | Same image, kept under its ordered name. |
| `thumbnail-2-corridor.png` | 1920×1080 | Second thumbnail. |
| `thumbnail-3-arsenal.png` | 1920×1080 | Third thumbnail. |
| `icon-512.png` | 512×512 | **Game icon.** Creator Dashboard → your experience → Basic Settings → Game Icon. This is the square shown in the games list and on mobile. |

## Uploading

1. https://create.roblox.com/dashboard/creations → select the experience.
2. **Basic Settings** → Game Icon → upload `icon-512.png`.
3. **Thumbnails** → upload `store-primary-1920x1080.png` first, then the other
   two in order. Drag to reorder if they land wrong; the first one is the one
   players see in search.
4. Both go through Roblox moderation, usually within minutes.

Set the experience name to **Fight to Escape the Backrooms** to match the art.

## Regenerating

```bash
python3 assets/branding/generate.py
```

Needs Pillow (`pip install --user Pillow`). Palette constants at the top of
that script mirror `Config.Level`, so if the level's colours change, update
them there too and re-render.
