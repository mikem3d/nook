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
| `rooms/<id>_bg.png` | 192x108 | Opaque. Wall, floor, window, shelves. Keep the top 11 px calm: the header bar covers it. Keep the upper right calm: the speech bubble sits there. |
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

Adding an animation = add a row, add an entry in `manifest.json`. Extra idle flourishes are picked at random if listed in `FLOURISHES` in `src/main.rs`.

## Generation pipeline (to be proven)
1. Generate at high resolution with a fixed style prompt plus the same character reference every time.
2. Downscale with nearest-neighbour to the target size, quantise to the shared palette, threshold alpha.
3. Animations are the hard part: separately generated frames drift. Generate a whole row as one strip from a reference frame, or use a pixel-art-specific animation model, then hand-check against the placeholder timing.
4. `tools/make_placeholders.py` regenerates the placeholder set and the manifest, and documents exact sizes.
