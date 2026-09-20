# Art pipeline: from raw AI output to contract-compliant assets

`docs/ART.md` is the contract (sizes, rows, frame counts). This document is how to get
AI-generated art to satisfy it, and how to see when it does not. The tools live in
`tools/art/` and need Python 3.12 with Pillow and numpy (`pip install -r tools/art/requirements.txt`).

No tool here calls an image generator or any network service. You generate images
wherever you choose, save them to disk, and feed the files in.

## The two problems these tools exist for

1. **Fake pixels.** Image models draw "pixel art" as a large image whose blocks are soft,
   unevenly sized and off any true grid, in thousands of colours. The engine needs one art
   pixel per PNG pixel, hard edges, binary alpha and one shared palette.
2. **Drift.** Frames generated separately do not show the same character: the head changes,
   the shirt changes shade, the body grows or slides. At 32x32 and 3 to 8 fps this reads as
   flicker.

`normalize.py` fixes the first. Nothing fixes the second after the fact, so `sheet.py
validate` and `consistency.py` measure it and refuse bad rows, and `preview.py` lets you
see it. Regenerate what fails.

## Tools

| Tool | Does |
|---|---|
| `normalize.py MODE in.png -o out.png` | Detect the fake-pixel grid, take one colour per cell, quantise to the palette, binary alpha, clean specks, optional outline, fit to contract size. Modes: `room-bg`, `room-fg`, `character-frame`, `character-strip`, `prop`. |
| `sheet.py split / assemble / validate` | Cut strips into frames, build `character/sheet.png` from per-animation strips, check a set against the theme (`theme.json`): sheet, scenes, props, frame and connector seams, orb, palette. Exit code 1 on any error. |
| `consistency.py sheet.png` | Frame-to-frame drift metrics per row, flags, JSON report. Exit code 1 if any row is flagged. |
| `preview.py --assets set/ -o out/` | Labelled 4x contact sheet, one GIF per animation at manifest fps, scene composites (still and animated), stacked chambers with open connectors, the orbs. |
| `install.py set/` | Validates, then copies into `Sources/Nook/Assets` with a backup. **Dry run unless `--apply`.** Never touches `manifest.json` or `theme.json`. |
| `palette.py list / extract / swatch` | List bundled palettes, derive one from reference images (median cut), render a swatch. |
| `tests/run_tests.py` | End-to-end tests on synthetic "AI-like" input. |

All tools take `--help`. All read the current theme through `Sources/Nook/Assets/manifest.json` (which names `themes/<id>/theme.json`; every set path below starts with `themes/<id>/`)
unless `--manifest` is given, so adding an animation row there is picked up automatically.

### How normalize.py works, and its knobs

1. **Grid detection.** Strong colour edges are thinned to their centre line, then their
   positions are folded modulo a candidate period; the true fake-pixel size concentrates
   them at one phase. It runs on the raw and on a lightly blurred copy (for noisy, soft
   sources) and resolves harmonics (s/2, 2s). The report prints `scale`, `phase` and a
   `confidence`; below 0.15 it warns that the source is probably not on a grid. Override
   with `--scale S [--phase X Y]`. For rooms, a detected grid within 4% of 192x108 is
   snapped to the canvas exactly; otherwise it falls back to an off-grid resample and says so.
2. **Sampling.** Only the core of each cell is read (the rim is where blur and
   anti-aliasing live). `--sample median` (default) takes the per-channel median of the
   core, `mode` takes the most common palette colour, `centre` the single centre pixel.
   No averaging across cell borders ever happens. Median won the round-trip tests under noise.
3. **Palette.** `--palette NAME|file.hex|auto`. With `auto` and `--palette-ref img...` the
   palette is median-cut from those references; with `auto` alone it is derived from the input
   (fine for experiments, wrong for production because each asset gets its own palette).
4. **Alpha.** `--key auto` uses the source alpha if it has any, otherwise the corner colour
   (that is what the magenta background in the prompts is for). `--alpha-threshold` 128.
5. **Cleanup.** `--orphans safe` removes opaque specks floating in transparency and 1px
   pinholes. It deliberately keeps isolated pixels inside the sprite: at 32x32 an eye is one
   pixel. `--orphans all` removes every isolated pixel; check the preview if you use it.
6. **Outline.** `--outline outer` draws the contract's 1px outline in the palette's darkest
   colour (`inner` recolours the sprite's rim instead, keeping its size).
7. **Fit.** Rooms are centre cropped or padded to 192x108. Character frames are anchored
   feet-first: the centre of the lowest three rows goes to x=16, the lowest pixel to the bottom
   row (`--anchor bbox|cell` and `--ground strip` change this). Strips are cut at transparent
   gaps when exactly N sprites are found, otherwise into equal widths. If the sprite is taller
   than 32 art pixels on its own grid, it is resampled off-grid to fit and a warning tells you;
   prefer regenerating, and reuse one `--scale` for every strip so all rows share a size.

### Bundled palettes (`tools/art/palettes/*.hex`)

| File | Colours | Author | Source |
|---|---|---|---|
| `pico8.hex` | 16 | Lexaloffle Games | lexaloffle.com/pico-8.php, lospec.com/palette-list/pico-8 |
| `sweetie16.hex` | 16 | GrafxKid | lospec.com/palette-list/sweetie-16 |
| `endesga32.hex` | 32 | Endesga | lospec.com/palette-list/endesga-32 |

These are widely used and published for free use, with credit expected. Verify the terms on
the source pages before shipping, and credit the author in the app's acknowledgements.
Format: one `RRGGBB` per line, `;` starts a comment. Pick ONE palette for the whole product.
Sweetie 16 or Endesga 32 suit a warm room; PICO-8 is harsher and more "console".

## End-to-end workflow

Work in a scratch folder laid out like the Assets folder (called `set/` below). Keep every raw
generation under `raw/` so a row can be re-normalised with other settings without paying again.

```sh
T=tools/art; PAL=sweetie16          # choose once, never change mid-project

# 1. Character reference (one frame). Everything else is generated from this image.
python3 $T/normalize.py character-frame raw/ref.png -o work/ref.png --palette $PAL --outline outer
#    Note the "scale" it prints. If the generator keeps its output size, reuse it below.

# 2. One strip per animation (frame count comes from the manifest via --anim)
python3 $T/normalize.py character-strip raw/idle_sip.png -o work/strips/idle_sip.png \
        --anim idle_sip --palette $PAL --outline outer            # add --scale S to pin size
#    ... repeat for all 11 animations ...

# 3. Sheet. --fill-from keeps rows you have not replaced yet.
python3 $T/sheet.py assemble work/strips -o set/themes/dwarf-mine/character/sheet.png \
        --fill-from Sources/Nook/Assets/themes/dwarf-mine/character/sheet.png

# 4. Rooms
python3 $T/normalize.py room-bg raw/forge_bg.png -o set/themes/dwarf-mine/scenes/forge/bg.png --palette $PAL
python3 $T/normalize.py room-fg raw/forge_fg.png -o set/themes/dwarf-mine/scenes/forge/fg.png --palette $PAL

# 5. Gates (both exit non-zero on failure)
python3 $T/sheet.py validate --assets set --palette $PAL
python3 $T/consistency.py set/themes/dwarf-mine/character/sheet.png --json work/consistency.json

# 6. Look at it
python3 $T/preview.py --assets set -o work/preview

# 7. Install: dry run first, then for real (backs up what it replaces)
python3 $T/install.py set --palette $PAL
python3 $T/install.py set --palette $PAL --apply
```

Foreground layers: generating a room and its foreground separately rarely lines up. The
reliable route is to generate ONE full room image, normalise it as `room-bg`, then make the
foreground by erasing everything except the desk and props in a pixel editor (or generate the
desk alone on magenta and normalise with `room-fg`). `validate` warns if nothing solid
stands in front of the character's boots (the bench top is at row 84, see docs/ART.md).

## Prompt templates

The point of these templates is that everything except one slot is identical in every
request. Keep the three blocks in a text file and paste them verbatim; do not paraphrase
between generations. Wording will need tuning per generator: these have not been tried
against any real model yet.

**STYLE block (identical in every prompt)**
```
8-bit pixel art, authentic low resolution sprite work, large clearly visible square pixels
on a strict uniform grid, flat colours, no gradients, no anti-aliasing, no blur, no
dithering, no texture, no lighting effects, hard 1 pixel dark outline, limited palette of
16 colours: <PALETTE NAME> palette (<paste the hex list>), front view, orthographic, no perspective
```

**CHARACTER block (identical in every character prompt; write yours once)**
```
the same character as the reference image: a small chibi developer, 32 pixels tall, big
head about 10 pixels wide, short dark brown hair with a straight fringe, two square black
eyes, no nose, no mouth, plain orange long sleeve shirt, dark blue trousers, no shoes
detail, no logo, no glasses, no accessories, standing, facing the viewer, feet together
```

**NEGATIVE block (use the generator's negative prompt field if it has one; verify)**
```
anti-aliasing, smooth shading, gradient, blur, soft edges, photo, 3d render, realistic,
high detail, noise, grain, jpeg artefacts, isometric, perspective, side view, three-quarter
view, drop shadow, ground shadow, floor, scenery, text, letters, watermark, signature,
border, frame, grid lines, extra limbs, extra characters, different outfit, different hair
```

**Character reference sheet** (generate until one is right; it is the anchor for everything)
```
<STYLE>. <CHARACTER>. Single character, idle standing pose, arms at the sides, centred,
full body visible with empty margin all around, on a plain flat solid magenta (#FF00FF)
background, nothing else in the image.
```

**Animation strip** (one request per animation; attach the normalised reference, upscaled
with nearest-neighbour, as the reference or init image if the generator accepts one)
```
<STYLE>. <CHARACTER>. Sprite sheet: a single horizontal strip of exactly <N> frames of the
same character, evenly spaced in one row, equal size, equal spacing, feet on the same
baseline in every frame, the character stays in the same place in every frame, only
<WHAT MOVES> changes between frames. Animation: <ACTION, frame by frame>. Plain flat solid
magenta (#FF00FF) background, clear magenta gap between frames, no frame borders, no
numbers, no labels, nothing else in the image.
```
Slots per row (N is fixed by the manifest):

| Animation | N | WHAT MOVES / ACTION |
|---|---|---|
| idle_breathe | 4 | only the torso and eyes: rest, chest up 1 pixel, chest up, eyes closed blink |
| idle_sip | 6 | only the right arm and a white mug: mug low, mug to face, drinking eyes closed, drinking, mug at face, mug low |
| idle_stretch | 6 | only the arms: arms out, arms up, arms up eyes closed, arms up, arms out, rest |
| idle_read | 8 | only arms, book, head: holds blue book, reads, glance right, turns page, glance left, lowers book |
| idle_look | 6 | only the head and eyes: looks left, left, centre, right, right, centre |
| think | 4 | only the right hand and dots: hand on chin, then one, two, three white dots above the head |
| type | 4 | only the forearms: hands alternate up and down in front of the body, fast typing |
| talk | 4 | only one arm and a slight lean: gestures right, right, left, left |
| alert | 2 | only the left arm: arm raised waving, red exclamation mark beside the head in frame 1 |
| celebrate | 6 | only the arms: arms out, arms up with yellow sparkles, arms up, sparkles, arms out, rest eyes closed |
| sleep | 4 | only the head and Zs: eyes closed, head sinks 1 pixel, white Z letters rise beside the head |

**Room background**
```
<STYLE without the outline clause>. Interior of a cosy <THEME> room, straight-on front view
of the back wall and a strip of floor at the bottom, 16:9. A window on the left, a shelf
with books on the right at mid height. The top tenth of the image is plain empty wall.
The upper right corner is plain empty wall. The centre of the room is empty floor and
wall: no desk, no chair, no character, no people, no text.
```

**Room foreground** (or cut it from the background by hand, see above)
```
<STYLE>. A wide wooden desk seen straight from the front, desk top edge at two thirds of
the image height, a laptop on the right half of the desk, a small mug on the left, a
potted plant standing on the floor at the far right. Plain flat solid magenta (#FF00FF)
background, nothing else, no character, no chair, no wall, no floor.
```

Practical notes:
- Ask for an output size that is an integer multiple of the target (rooms: 1536x864 = 8x,
  or 1920x1080 = 10x) if the generator lets you choose; verify what sizes it offers.
- A model asked for "32 pixels tall" will not count pixels. What matters is that its fake
  pixels are large: the character should be roughly 32 fake pixels tall. If it draws 64, the
  detail cannot survive; regenerate with "bigger pixels, lower resolution, fewer details".
- Naming the palette helps the look but no general model will hit exact hex values;
  quantising is what enforces the palette. Expect some colours to snap to a neighbour you
  did not intend; if one keeps going wrong, change the prompt colour word, not the palette.
- Fix the seed if the generator exposes one, and change only the ACTION slot. Verify whether
  your generator's seed actually gives repeatable output.

## Generation approaches for animation consistency

Nothing below has been tried for this project yet. No product names, features or prices are
asserted here on purpose: check each candidate's current documentation and terms (including
commercial use of outputs) before paying. "Verify" marks what to confirm in a trial.

| Approach | For | Against |
|---|---|---|
| **A. One strip per animation, with the reference image attached** | Frames in a strip come from one generation, so face, colours and proportions usually agree within the row. Matches the tooling directly (`character-strip`). Works with general image models. | Models miscount: asking for 6 frames can give 5 or 7 (verify; regenerate). Spacing is uneven (gap-based cutting copes). Rows still drift from each other, which `ref_head` / `ref_palette` measure. Motion is often too big or barely there. Needs a generator that accepts a reference image; how strongly it follows one varies (verify). |
| **B. Image-to-image from the idle frame, one frame at a time** | Strongest identity lock: every frame starts from the same pixels. Low denoise strength keeps the head almost untouched. Good for small motions (blink, breathe, look, type). | One request per frame: 54 frames. At low strength the pose hardly changes; at high strength identity goes. Large pose changes (arms up) usually need pose guidance or inpainting only the arms (verify availability). Each frame is on its own grid, so normalise every frame with the same pinned `--scale`. |
| **C. Dedicated pixel-art or sprite-animation models** | Built for true low-resolution output and sometimes for animating a given sprite, so grid and palette problems may mostly disappear and normalising becomes a formality. | Smaller vendors, faster-changing features and terms. Animation templates may be limited to walk/run/attack cycles rather than "sips from a mug" (verify). Native sizes may not include 32x32 (verify). Licence terms for commercial use vary (verify). |
| **D. Generate large and detailed, then normalise down** | Highest hit rate for an attractive image from general models; works well for rooms, where there is no animation. | Worst option for characters: fine detail collapses at 32x32 into noise, eyes vanish, outlines break. `normalize.py` will warn ("resampled off-grid") but cannot invent a readable sprite. Use for rooms only. |
| **E. Hybrid (recommended starting point)** | Rooms by D. Reference by many cheap tries. Small-motion rows by B or by hand-editing the reference in a pixel editor (a blink is two pixels). Big-motion rows by A or C. | More moving parts; needs the gates below on every row. |

Honest expectation: with any of these, some rows will need manual pixel clean-up after
normalising (a stray eye pixel, a broken outline). At 32x32 that is minutes per row, and a
hand-fixed frame still passes through `validate` and `consistency` like any other. Editing
2 pixels for a blink is more reliable than any generator; the "all art is AI generated"
goal is best read as "AI generated, machine normalised, lightly hand corrected".

## Acceptance checklist

Per asset set, before `install.py --apply`:

- [ ] One palette chosen and used for every file (`--palette` identical everywhere).
- [ ] `sheet.py validate --assets set --palette PAL` exits 0. That covers: sheet 256x352, 8
      columns of 32x32, 11 rows with the manifest frame counts, no empty required frame, no
      junk in unused columns, feet on the bottom row, feet centred within 1.5 px and drifting
      at most 1 px in a row, binary alpha, every pixel in the palette, at most 32 colours
      across the set, rooms 192x108, backgrounds fully opaque, foregrounds transparent.
- [ ] Validate warnings read and accepted or fixed: outline coverage, frames touching the
      frame edge, busy header strip (top 11 px), busy upper right (speech bubble), no bench
      in front of the character, connector seams that do not line up, orb art outside the circle.
- [ ] `consistency.py` exits 0, or every flagged row was looked at and is legitimate motion
      (then record the `--set key=value` override you used).
- [ ] No normalize warning about "off-grid" or "weak pixel grid" on character art.
- [ ] Contact sheet: same face, hair and shirt in every row; eyes present in every frame.
- [ ] GIFs at real speed: no flicker, no size pumping, no sliding feet; loops loop cleanly
      (last frame leads back into the first); one-shot rows end in the idle pose.
- [ ] Composites: desk hides the legs, character is not floating or sunk, nothing important
      under the header bar or the bubble, character reads against the wall colour.
- [ ] In the app at 2x in a corner: still readable. (Needs the engine owner; not covered here.)

## Thresholds used by consistency.py

Every metric compares a frame with the **first frame of its row**; the `ref_*` metrics
compare each row's first frame with the sheet's reference frame (`idle_breathe[0]`).

| Key | Value | Meaning |
|---|---|---|
| `iou_min` | 0.60 | silhouette intersection-over-union |
| `area_min` / `area_max` | 0.80 / 1.25 | silhouette area ratio (size pumping) |
| `palette_max` | 0.30 | colour histogram distance, 0..1 |
| `com_dx_max` / `com_dy_max` | 2.5 / 3.0 px | centre-of-mass offset |
| `head_min` | 0.75 | share of identical pixels in the head box, best over +/-2 px shifts |
| `ref_head_min` | 0.75 | same, row's first frame vs reference frame |
| `ref_palette_max` | 0.30 | histogram distance, row's first frame vs reference frame |
| `ref_area_min` / `ref_area_max` | 0.75 / 1.40 | area ratio vs reference frame |

The head box is found from the column above the feet (14 px wide, top 40% of the body), so
marks beside the head (Zs, "!", sparkles) do not disturb it.

**How they were chosen.** Two measurements, both synthetic:

1. The hand-made placeholder sheet is known-good animation with deliberate motion (arms up,
   props, leaning, bobbing). Its extremes set what must pass: lowest IoU 0.70 (celebrate),
   lowest head match 0.83 (idle_stretch, eyes closed plus a bob), highest histogram distance
   0.24 (idle_read, where the book disappears in the last frame), area 0.90 to 1.15,
   centre-of-mass range 1.5 px sideways (talk) and 2.3 px vertically (celebrate), lowest
   `ref_head` 0.91, highest `ref_palette` 0.24.
2. `tests/synth.py drift_row` injects one fault at a time into a clean row. Growth of 4% per
   frame gives area 1.35 and head 0.50; a slide of 1 px per frame gives centre-of-mass 4.7 px
   and IoU 0.41; the shirt switching to another palette colour gives histogram distance 0.47.

Each threshold sits between the two, closer to the legitimate side so that real drift is not
waved through. They are **not** calibrated on real AI output. Expect to retune after the
first real batch: if good rows are flagged, loosen with `--set`, note the value here, and
change `THRESHOLDS` in `consistency.py`. Known blind spots: a prop appearing legitimately
moves the histogram (0.24 of the 0.30 budget in idle_read); the head metric compares exact
pixels, so a face redrawn in a slightly different but equally good way will be flagged, which
is intended (at 32x32 that is visible flicker); nothing here judges whether the motion is good.

## What the tests prove, and what they do not

`python3 tools/art/tests/run_tests.py` (about a minute) degrades the placeholder art the way
AI output is degraded (non-integer upscale 7.3x/8x/10.67x, Gaussian blur, noise, colour cast,
JPEG), normalises it back, and checks: grid detection within 1% at nine scales from 3x to 20x;
every file at least 99.5% pixel-identical to the source (residual errors are between two
near-identical dark colours in the test palette); the assembled set passes `validate`; eight
kinds of broken sheet are each rejected with the right message; clean rows pass `consistency`
and size, position and colour drift are each flagged; outline, orphan, prop, split, preview
and install (dry run, apply, backup, restore, refusal) behave. The installed placeholder
theme itself passes `validate` against its own 28-colour palette, and a ladder that misses the
seam or orb art outside the circle is rejected.

Unproven until real generations are tried: grid detection on real model output (uneven or
warped fake pixels, inconsistent pixel size inside one image, painterly "pixel art" with no
grid at all); how well quantising to a fixed palette preserves a model's colours; whether
gap-based strip cutting copes with overlapping frames or miscounted strips; whether the drift
thresholds separate good from bad on real rows; and every prompt template above.
