# Art contract

Every window is a CHAMBER cut into a mountain. Rock surrounds it; where two docked windows touch,
the rock opens and a ladder (above/below) or a tunnel (left/right) joins them. A minimised window is
a round ORB with the agent's head in it. A THEME supplies all of that art; the first one is the dwarf
mine. All art is AI generated later, then normalised to this contract. What ships now are
placeholders from `tools/make_placeholders.py`, which also documents every size by construction.

## Layout on disk
```
Assets/manifest.json                     {"theme": "dwarf-mine"}   the default theme
Assets/fonts/                            Departure Mono (not part of a theme)
Assets/themes/<theme>/theme.json         everything below; paths are relative to this folder
Assets/themes/<theme>/character/sheet.png, portrait.png
Assets/themes/<theme>/frame/frame.png, ladder_top.png, ladder_bottom.png, tunnel_left.png,
                            tunnel_right.png, sealed_top.png, sealed_bottom.png, sealed_left.png, sealed_right.png
Assets/themes/<theme>/orb/back.png, ring.png, gem.png, alert.png, work.png
Assets/themes/<theme>/props/<name>.png
Assets/themes/<theme>/scenes/<scene>/bg.png, fg.png, <ambient>.png
```
Swap a PNG and it shows up on next launch. Only `character` and `scenes` are required in
`theme.json`; anything else that is missing is simply not drawn (no frame: a plain header bar; no
orb art: a plain disc; no portrait: the head of the first character frame; no bg: a flat fill).

## Global rules
- Canvas: 192x108 px. Shown at 1x, 1.5x or 2x. Never resample with smoothing.
- True pixel grid: one art pixel = one PNG pixel. No anti-aliasing, no gradients, no sub-pixel edges.
- ONE shared palette per theme, at most 32 colours, listed in `theme.json` `palette` ("rrggbb").
  Every opaque pixel of every file must be one of them. `sheet.py validate` enforces it.
- Hard 1 px dark outline on the character and the portrait, none required elsewhere.
- PNG, RGBA. Alpha is fully on or fully off.
- Positions in `theme.json` are the sprite's BOTTOM-LEFT, in canvas pixels from the canvas
  bottom-left. Rows below are given from the TOP, as an image editor shows them.
- Draw order (`z`): background 0, character 1, foreground 2, things on the bench 2.5, frame 10, connectors 11.

## Chamber geometry (the same for every scene of every theme)
| What | Where (x from left, rows from top) |
|---|---|
| Header lintel | rows 0..10, part of `frame.png`. Keep it dark and calm: the title is white text on it. |
| Side rock | x 0..5 and 186..191 |
| Floor | row 90 is the floor surface; rows 90..107 are rock. Feet stand at y=18 from the bottom. |
| Chamber interior | x 6..185, rows 11..89 |
| Ladder shaft | x 12..25 (centre 19) on BOTH the top and the bottom edge |
| Tunnel mouth | rows 62..91 on BOTH the left and the right edge, 10 px deep |
| Header, left to right | state gem x 4..8, ladder hatch x 12..25, title from x 30, unread badge ending at x 166, minimise x 168..179, close x 180..191 |

Zones a scene must respect:
- x 12..25, all rows: only wall. The ladder hangs here when the chamber above is connected.
- x 0..9 and 182..191, rows 62..91: only wall. The tunnel pieces cover it.
- x 32..62: the vitals wall (skylight, shelf, jar, clock), unless the scene places them elsewhere.
- x 84..115: the character (feet at x 100). The bench stands in front: top at row 84, x 66..133, so the
  lowest 6 px of the character are hidden.
- x 136..180: the scene's own feature (forge, oven, still, bunks).
- Upper right, x 40..188, rows 13..58: keep calm, the speech bubble covers it.

## Frame and connectors
`frame.overlay` (192x108) is the rock: opaque border, transparent interior. Each edge has an `open`
and a `sealed` piece, each `{ "sprite", "position" }`:

| Edge | Open piece | Placeholder size, position | Sealed piece |
|---|---|---|---|
| top | `ladder_top.png`: shaft through the lintel, then the ladder down to the floor | 14x90 at [12, 18] | `sealed_top.png` 14x11 at [12, 97]: a hatch |
| bottom | `ladder_bottom.png`: ladder top poking 10 px above the floor, shaft down through the rock | 14x28 at [12, 0] | `sealed_bottom.png` 14x3 at [12, 16]: a trapdoor |
| left | `tunnel_left.png`: timbered mouth, dark tunnel, the floor carried through | 10x30 at [0, 16] | `sealed_left.png`, same place: boarded up |
| right | `tunnel_right.png`: the mirror image | 10x30 at [182, 16] | `sealed_right.png` |

Seam rules (windows abut with NO gap, at the same scale, and any scene can meet any other):
1. `top.open` and `bottom.open` have the same x and width; the top piece touches the top edge and
   the bottom piece the bottom edge.
2. The TOP ROW of `top.open` equals the BOTTOM ROW of `bottom.open`, pixel for pixel, and is opaque.
   Paint anything periodic (rungs every 4 rows) from the canvas row, and 108 is a multiple of 4.
3. `left.open` and `right.open` have the same y and height; the left piece starts at x=0, the right
   one ends at x=191; the OUTER COLUMN of each equals the other's. Mirroring one piece does it.
4. The floor (rows 90, 91) continues through the tunnel.
`sheet.py validate` and `ThemeTests.testConnectorsAlignAcrossSeams` check rules 1 to 3.

## Scenes
```json
{ "id": "forge", "name": "Forge", "bg": "scenes/forge/bg.png", "fg": "scenes/forge/fg.png", "feet": [100, 18],
  "props": [{ "name": "papers", "position": [69, 24], "z": 2.5 }],
  "ambient": [{ "name": "fire", "sheet": "scenes/forge/fire.png", "frame": [20, 16], "frames": 4, "fps": 5, "position": [150, 24], "z": 0.5 }],
  "animations": { "type": "hammer" } }
```
| Key | Meaning |
|---|---|
| `id`, `name` | `id` is stable and persisted; `name` is what the scene menu shows. Order is the round-robin order for new agents. |
| `bg` | 192x108, opaque. The back wall and furniture behind the character. Rows 0..10 flat. |
| `fg` | 192x108, transparent except what stands in front of the character (the bench and what is on it). |
| `feet` | Bottom-centre of the character frame. Optional; defaults to `character.feet`. |
| `props` | Where THIS scene puts the theme's vitals props. A prop not listed is absent; no `props` key means all at their defaults. |
| `ambient` | Optional looping strips, frames side by side. `fps` at most 6 (more would raise the window's frame rate). Optional `"path": {"to": [x, y], "seconds": 6, "every": 18}` glides the sprite from `position` to `to`, then hides it until the next pass; hide the ends behind `fg`. Reduce Motion freezes them. |
| `animations` | Replaces a default animation in this scene: `"type": "hammer"` makes the working pose hammering. The replacement must be a row of the character sheet; otherwise the default plays. |

Dwarf mine scenes: workshop (ore cart passing in the gallery), forge (flickering fire, hammering),
bakery (oven glow, bread steam, kneading), distillery (bubbling still, dripping pipe, stirring), lab
(fizzing flask, stirring), treasury (glinting gold), mushrooms (spores, dripping water), quarters
(candle, a snoring bunkmate).

## Character sheet
`character/sheet.png`: 32x32 frames, 8 columns, one row per animation, facing the viewer, feet on
the bottom edge of the frame, centred horizontally, never touching the other three edges.

| Row | Name | Frames | FPS | Loop | What it shows |
|---|---|---|---|---|---|
| 0 | idle_breathe | 4 | 3 | yes | breathing, a blink |
| 1 | idle_sip | 6 | 5 | no | lifts a tankard, drinks, puts it down |
| 2 | idle_stretch | 6 | 5 | no | arms up stretch |
| 3 | idle_read | 8 | 4 | no | reads a book, turns a page |
| 4 | idle_look | 6 | 4 | no | looks left, then right |
| 5 | think | 4 | 3 | yes | hand on chin, dots appear |
| 6 | type | 4 | 8 | yes | busy hands on the bench: the default "agent is using a tool" pose |
| 7 | talk | 4 | 5 | yes | stance shifts and gestures |
| 8 | alert | 2 | 4 | yes | waves with "!": the agent needs permission |
| 9 | celebrate | 6 | 8 | no | arms up, sparkles: task finished |
| 10 | sleep | 4 | 2 | yes | eyes closed, Zs: no activity for 5 minutes |
| 11+ | optional work poses | up to 8 | up to 8 | yes | dwarf mine: `hammer`, `knead`, `stir`. A scene opts in through `animations`. |

Rows 0 to 10 are the engine's contract. Adding an animation = add a row and an entry in
`character.animations`. Extra idle flourishes are picked at random if listed in `flourishes` in `RoomScene.swift`.

## Avatars: several characters from one sheet
`avatars` is a list of `{ "id", "name", "swap": { "rrggbb": "rrggbb" } }`. The engine recolours the
sheet AND the portrait at load time by exact colour match, so every agent is recognisably someone
else. The agent's folder path picks the avatar (FNV-1a hash), the same one on every launch.
- Reserve KEY colours for what varies and use them for nothing else in the sheet or the portrait.
  Dwarf mine: beard `ee8a3a`/`a8713f`, tunic `4f9a5a`/`2f5d43`, helmet `8f8ca0`/`63607a` (main/shade).
- Swap targets must be in the theme palette. The first avatar has an empty swap: the sheet as drawn.

## Portrait and orb (minimised window)
The window becomes 28x28 art px and the scene draws only this, bottom to top:
| Layer | File | Size | Notes |
|---|---|---|---|
| back | `orb/back.png` | 28x28 | disc behind the head |
| portrait | `character/portrait.png` | 20x20 per frame at `orb.portraitPosition` [4, 4] | head only, one frame per state; `portrait.states` maps `idle, thinking, working, talking, alert, done, sleeping` to frame indices. Corners end up under the ring. |
| ring | `orb/ring.png` | 28x28 | the theme's round border (rock and iron), with its own dark rim: the window has NO shadow |
| work | `orb/work.png` | 4 frames of 10x10 at [18, 1], 4 fps | shown while working: a tiny pick swinging |
| alert | `orb/alert.png` | 28x28 | rim overlay blinked twice a second while the agent needs permission |
| gem | `orb/gem.png` | 6x6 at [11, 0] | drawn LIGHT (white and pale): the engine multiplies it by the state colour |
Nothing may be opaque outside the inscribed circle (validated). The engine adds the unread badge over
the top right and bobs it by one pixel. Orbs redraw at 4 fps, and only while alert, working or unread.

## Props: the chamber as a dashboard
One PNG sheet per prop, states side by side, declared once in `theme.json` `props`
(`name, sheet, frame, states, position, z`) and placed per scene. The `name` decides the meaning:

| Name | Placeholder | States | Shows |
|---|---|---|---|
| `window` | skylight, 26x20 at [33, 70] | 3: day, dusk, night | Real time of day: day 08 to 17, dusk 06 to 08 and 17 to 20, night otherwise. |
| `bookshelf` | 30x30 at [32, 18] | 11: 0 to 10 books | Context used, in even steps. Above 85% the engine tints it red; keep it readable under a red wash. |
| `coinjar` | 10x12 at [35, 48] | 9: empty to full | Session cost on a log scale: empty under $0.01, full at $20. |
| `clock` | 13x13 at [48, 48] | 8 hand positions, clockwise from twelve | Steps once a second while a turn runs, rests at twelve otherwise. |
| `papers` | 14x8 at [69, 24], on the bench | 6: 0 to 5 sheets | Uncommitted files; the last state means "5 or more". State 0 is fully transparent. |
| `hourglass` | 8x10 at [123, 24], on the bench | 4: sand running down | Hidden until a turn passes 5 minutes, then cycles one state a second. |
`states` can be any number of 1 or more; the engine spreads the value over however many you draw.

## Text
Header, badge and speech bubble use Departure Mono (`fonts/DepartureMono-Regular.otf`, SIL OFL 1.1,
licence alongside). It is drawn one font pixel per image pixel with no smoothing, then scaled like the
art: one font pixel is one art pixel at 1x and 1.5x, half an art pixel at 2x, so glyph pixels always
land on the art grid. Every glyph sits in a 7x11 cell. The bubble (box, clipped corners, stepped tail,
"more" arrow), the state gem in the header and the minimise and close glyphs are drawn by the engine.

## Tools
- `python3 tools/make_placeholders.py` regenerates the placeholder theme, `theme.json`, the root
  manifest and `tools/art/palettes/dwarfmine.hex`. The palette is a table in
  `tools/placeholders/pixels.py`; saving a pixel outside it fails, so the 32-colour rule holds by construction.
- `python3 tools/art/sheet.py validate` checks the installed theme: sizes, alpha, palette, colour
  count, feet, drift, seams, orb circle, avatar swaps. `--assets set/ --palette name` checks a candidate.
- `python3 tools/art/preview.py -o out/` writes contact sheet, GIFs, a composite per scene, stacked
  chambers with open connectors (`stack_vertical.png`, `stack_horizontal.png`, `stack_mountain.png`) and `orbs.png`.
- `NOOK_PREVIEW=out/ swift test --filter PreviewTests` renders the same through the real engine.
- See `docs/ART_PIPELINE.md` for turning AI output into contract-clean files.
