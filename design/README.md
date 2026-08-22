# KeyPort artwork

Regenerate everything (except the two `raw/` paintings) with:

```bash
python design/make_art.py
```

## What goes where on CurseForge

| File | Size | Upload to |
| --- | --- | --- |
| `keyport-icon-400.png` | 400×400 | Project **Avatar** (Settings → General) |
| `keyport-banner.png` | 840×420 | Top of the **Description** |
| `keyport-gallery-picker.png` | 840×472 | Description body, and the **Images** gallery as primary |
| `keyport-gallery-command.png` | 840×472 | Description body, and the **Images** gallery |
| `keyport-gallery-codes.png` | 840×472 | Description body, and the **Images** gallery |
| `keyport-picker.png` | 688×504 | The keystone list on its own |
| `keyport-popup.png` | 660×426, transparent | The popup on its own; spare for Discord, Reddit |
| `keyport-icon-64.png` | 64×64 | Not uploaded; a check that the avatar survives the listing thumbnail |
| `full-size/*.png` | 1280 wide | Optional: upload these to the **Images** gallery, where the lightbox shows them full size |

CurseForge's description column clips images wider than about 850px, so every
body image is capped at 840. `BODY_W` in `make_art.py` sets that; the uncut
renders go to `full-size/`.

## How it's built

* `raw/icon-portal.png` and `raw/banner-portal.png` are the only painted assets;
  both were generated with OpenAI's `gpt-image-2`. Everything else is composed
  from them in Pillow. Regenerating the paintings is a separate, manual step;
  `make_art.py` only consumes them.
* The popup and the keystone list in every image are **not** screenshots. They
  are drawn in `make_art.py` from the same layout constants as `KeyPort.lua`
  (`PANEL_W`, `HEADER_H`, `BUTTON_Y`, `LIST_W`, `ROW_H`, …), so they match the
  real frames' proportions, colours and copy. If you change the addon's layout, change the
  constants at the top of `make_art.py` to match.
* The teleport icon inside the popup is a drawn stand-in glyph, not Blizzard's
  spell icon. The real one comes from the game at runtime.
* Fonts: Georgia Bold stands in for Friz Quadrata (WoW's UI face, which isn't
  distributable), Cinzel Decorative carries the wordmark, Segoe UI and Consolas
  handle body copy and commands.

## Worth doing before launch

Replace `keyport-gallery-command.png` as the primary gallery image with a real
in-game screenshot of the popup in a party. Mockups sell the idea, but a
genuine screenshot is what players trust. Everything else can stay.
