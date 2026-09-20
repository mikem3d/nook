# Art contract

All art is AI generated, then normalised to this contract. The engine reads
`assets/manifest.json`; swap a PNG and it shows up on next launch.

## Global rules
- Canvas: 192x108 px (16:9). Shown at 2x in the corner, 5x expanded. Never resample with smoothing.
- True pixel grid: one art pixel = one PNG pixel. No anti-aliasing, no gradients, no sub-pixel edges.
- One shared palette across every asset, 16 to 32 colours (pick one, e.g. a NES-style or PICO-8-style set).
- Hard 1px dark outline on the character, none required on backgrounds.
- PNG, RGBA. Alpha is fully on or fully off.

## Per room (one room per agent session)
| File | Size | Notes |
|---|---|---|
| `rooms/<id>_bg.png` | 192x108 | Opaque. Wall, floor, the window frame. Keep the top 11 px calm: the header bar covers it. Keep the upper right calm (x 40 to 188, y 13 to 58 from the top): the speech bubble sits there. Do not paint the vital-sign props below into the room; leave their spots plain. |
| `rooms/<id>_fg.png` | 192x108 | Transparent except what stands in front of the character: desk, laptop, plant. Desk top edge at y=70 from the top. |

Character feet sit at x=84, y=26 from the bottom-left (`character.feet`), so the desk hides the legs.

## Character sheet
`character/sheet.png`: 32x32 frames, 8 columns, one row per animation, facing the viewer, feet on the bottom edge of the frame, centred horizontally.

| Row | Name | Frames | FPS | Loop | What it shows |
|---|---|---|---|---|---|
| 0 | idle_breathe | 4 | 3 | yes | breathing, a blink |
| 1 | idle_sip | 6 | 5 | no | lifts a mug, drinks, puts it down |
| 2 | idle_stretch | 6 | 5 | no | arms up stretch |
| 3 | idle_read | 8 | 4 | no | reads a book, turns a page |
| 4 | idle_look | 6 | 4 | no | looks left, then right |
| 5 | think | 4 | 3 | yes | hand on chin, dots appear |
| 6 | type | 4 | 8 | yes | fast typing: the "agent is using a tool" state |
| 7 | talk | 4 | 5 | yes | stance shifts and gestures, mouth does not need to move |
| 8 | alert | 2 | 4 | yes | waves with "!": the agent needs permission |
| 9 | celebrate | 6 | 8 | no | arms up, sparkles: task finished |
| 10 | sleep | 4 | 2 | yes | eyes closed, Zs: no activity for 5 minutes |

Adding an animation = add a row, add an entry in `manifest.json`. Extra idle flourishes are picked at random if listed in `flourishes` in `RoomScene.swift`.

## Props: the room as a dashboard
Each room shows the agent's vital signs as small sprites, readable at a glance. A prop is one PNG
sheet with its states side by side, left to right, every state the same frame size. Props are
declared in `manifest.json` under `props`:

```json
{ "name": "bookshelf", "sheet": "props/bookshelf.png", "frame": [36, 34], "states": 11, "position": [4, 8], "z": 0.5 }
```

- `position`: bottom-left of the frame in canvas pixels, measured from the canvas bottom-left (like `character.feet`).
- `z`: draw order. Background 0, character 1, foreground (desk) 2. Use 0.5 for things on the wall or floor behind the character, 2.5 for things standing on the desk.
- `states`: any number of 1 or more; the engine spreads the value over however many you draw.
- A prop left out of the manifest, or whose sheet is missing, is simply not shown. The `name` decides what it means:

| Name | Placeholder | States | Shows |
|---|---|---|---|
| `window` | 40x30 at 20,54 | 3: day, dusk, night | Real time of day: day 08 to 17, dusk 06 to 08 and 17 to 20, night otherwise. Paint the sky and the glazing bars; the frame belongs to the room. |
| `bookshelf` | 36x34 at 4,8 | 11: 0 to 10 books | Context window used, in even steps; any use shows the first book. Above 85% the engine tints the whole sprite red, so keep it readable under a red wash. |
| `coinjar` | 10x12 at 26,42 | 9: empty to full | Session cost on a log scale: empty under $0.01, full at $20. |
| `papers` | 14x8 at 47,38 | 6: 0 to 5 sheets | Uncommitted files; the last state means "5 or more". State 0 is fully transparent. |
| `clock` | 13x13 at 3,67 | 8 hand positions, clockwise from twelve | The hand steps once a second while a turn runs and rests at twelve otherwise. |
| `hourglass` | 8x10 at 138,38 | 4: sand running down | Hidden until a turn passes 5 minutes, then cycles one state a second. |

Desk props stand on the desk top (y=38 from the bottom). Keep props out of the bubble area and away from x 68 to 100, where the character sits.

## Text
Header, badge and speech bubble use Departure Mono (`fonts/DepartureMono-Regular.otf`, SIL OFL 1.1,
licence alongside). It is drawn one font pixel per image pixel with no smoothing, then scaled like the
art: one font pixel is one art pixel at 1x and 1.5x, half an art pixel at 2x, so glyph pixels always
land on the art grid. Every glyph sits in a 7x11 cell. The bubble itself (box, clipped corners, stepped
tail, "more" arrow) is drawn by the engine in ink `#1A1A29` on white; rooms need no bubble art.

## Generation pipeline (to be proven)
1. Generate at high resolution with a fixed style prompt plus the same character reference every time.
2. Downscale with nearest-neighbour to the target size, quantise to the shared palette, threshold alpha.
3. Animations are the hard part: separately generated frames drift. Generate a whole row as one strip from a reference frame, or use a pixel-art-specific animation model, then hand-check against the placeholder timing.
4. `tools/make_placeholders.py` regenerates the placeholder set and the manifest, and documents exact sizes.
