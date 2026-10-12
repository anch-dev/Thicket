# Thicket

An original puzzle-action game for iPhone and iPad, written in Swift with SpriteKit.

Pip, a small forest sprite, walks the playfield and lifts, carries, drops and kicks pieces. The aim is to line up **Mites** with matching **Seeds** that Wren the bird drops from above. When Wren's meter fills, **the Gloom**, a storm cloud, takes over. It drops Mites and slams **the Canopy** down a row. Clear every Mite to win the round.

All names, characters, art, music and sound in Thicket are original. The art is authored as text in `scripts/sprites.py`. The music and sound effects are synthesized at runtime from note data in `Sources/ThicketKit/ChipSynth.swift`. The project contains no third-party assets.

## Rules

| | |
|---|---|
| Field | 7 columns × 13 rows (6 columns per side in Versus). Gravity settles every piece. |
| Match | 3+ same-colored pieces in a horizontal, vertical or diagonal line **that includes a Seed** (or Starseed). Three Mites alone never match. Overlapping lines resolve together. |
| Starseed | Clearing 5+ in one line grows a Starseed of that color. When a Starseed is part of a match, every Mite of its color is cleared. |
| Common Mite | Cleared by any valid line. |
| Slant Mite (stripes) | Only diagonal lines clear it. It breaks horizontal and vertical lines. |
| Shifter Mite (horns) | The first hit changes its color (Ember → Tide → Bloom → Ember). A second match in the new color clears it. |
| Flicker Mite (spark) | The first hit makes it flash for 4 s. It must be hit again while it is flashing. |
| Chains | Pieces that fall after a clear and then make a new match count as a chain step. Multipliers per step are ×1, ×2, ×3, ×5, ×8, ×12, ×16. A chain combo text appears on screen. |
| Phases | Wren drops Seeds while the meter fills. Then the Gloom drops Mites, and the Canopy slams down one row every few seconds. Each chain step shortens the Gloom phase. When Wren returns she pushes the Canopy up one row. |
| Losing | A stack touches the Canopy, or the Canopy slams down on Pip (and his load), or Pip is boxed in with no legal move for 1.5 s. Pieces that fall on Pip are **caught** and added to what he carries. |
| Rounds | 99 campaign rounds. Later rounds start with more Mites and taller stacks, drop pieces faster, and add Slant (round 8+), Shifter (16+) and Flicker (24+) Mites. |

Colors are chosen to be colorblind-friendly (based on the Okabe-Ito palette). Each color also has its own shape:

| Color | Mite shape | Seed emblem |
|---|---|---|
| Ember (orange) | round | ● |
| Tide (blue) | pointed | ▲ |
| Bloom (pink) | square | ■ |

Pieces that Pip is carrying are out of play. They don't match and Starseeds don't clear them.

## Modes

- **Rounds**: the 99-round campaign. Progress and best scores are saved.
- **Endless**: the field refills and difficulty rises every 45 s. Your best score is saved.
- **Time Trial**: three trails of 5 rounds each, played against the clock. Best times are saved. Losing a round restarts the trail.
- **Lessons**: 8 interactive steps covering walking, climbing, lifting, dropping, kicking, matching, stacking and Starseeds.
- **2P Versus** (iPad only): two 6-column fields. Chains, long lines and Starseeds send Mites to your opponent. Player 1 uses controller 1 or WASD+F/G. Player 2 uses controller 2 or the arrow keys plus `.`/`,`.

## Controls

| Action | Touch | Controller | Keyboard |
|---|---|---|---|
| Walk / turn | D-pad ←/→ (tapping the other way turns first) | D-pad / left stick | ←/→ or A/D |
| Climb the stack in front, one cell at a time (works while carrying if there's room) | Walk into it, or Up | same | same |
| Climb down while clinging | Down | Down | ↓ or S |
| Lift the piece in front **and everything above it** | A | A (south) | X or K |
| Pull out **only** the piece in front | B | B (east) | Z or J |
| Put down what you carry **in front** | Up, A+B, A or B | Up, X/Y, A or B | ↑, C/L/Space, X or Z |
| Put down what you carry **under Pip** (he stands on it) | Down | Down | ↓ or S |
| Kick the piece in front | Hold Down + A | Down + A | ↓ + X |
| Pause | II / START | Menu | Esc / P / Return |

Pip can only reach the piece directly in front of him at his own height.

The touch controls are fully multitouch:

- The D-pad keeps its finger until you lift it, even if the finger slides off the pad.
- A finger can roll between A, B and A+B.
- Any press shorter than a frame still counts.
- Every input is released when the app is interrupted.
- Presses made up to 8 frames before Pip is ready are buffered.

To customize the controls, go to **Settings → Edit touch controls**. You can drag controls to new positions and change their size and opacity. The layout is saved separately for each device size. The on-screen pad hides itself while a controller or keyboard is in use, unless *Always show touch controls* is on.

## Graphics

**Settings → Graphics** switches between:

- **3D** (default): a SceneKit forest. All the models are built from code: rounded Mites, acorn Seeds, star Starseeds, Pip, Wren, the Gloom and the Canopy. It has shadows, particles and landing markers for dropping pieces.
- **Pixel 2D**: the original SpriteKit pixel art.

Both modes draw the same simulation, and the HUD is pixel text in both.

## Logging (for bug reports)

- Logs are always written to `thicket-log.txt` in the app's Documents folder. In the Files app it's under *On My iPhone › Thicket*. Logs also go to the system log under the subsystem `dev.anch.thicket`.
- By default the log records: launches, settings, lifecycle, audio sessions, controllers, game starts and outcomes, a board dump on game over, and **every rejected action with the reason**, for example `rejected climb: no room on top of the stack (Canopy or falling piece)`.
- With **Settings → Verbose logging** turned on, it also records every input change, touch press and release, and game event.
- **Settings → View / Share log** shows the log and opens the share sheet.

## Project layout

```
Sources/ThicketCore/   Pure Swift game logic (no UIKit/SpriteKit): board, MatchFinder, resolver,
                       Pip actions, phases, scoring, seeded RNG, lessons, time trials, versus.
                       Fixed 60 Hz `GameState.step(_:)`, deterministic and Codable.
Sources/ThicketKit/    Pure Swift support: touch/D-pad model, input merging, keyboard map,
                       control layouts, persistence, session flow, chiptune synth, sprite data.
App/                   iOS app: SpriteKit renderer, touch view, GameController input,
                       AVAudioEngine output, haptics, SwiftUI menus.
Tests/                 ThicketCoreTests, ThicketKitTests (SwiftPM + simulator), ThicketAppTests (simulator).
scripts/sprites.py     Original pixel art as text → SpriteData.swift + app icon.
scripts/build.sh       Build and test on macOS.
project.yml            XcodeGen project (iOS 16+, iPhone + iPad, landscape only).
```

## Build, run and test

Requirements: macOS with Xcode 15.4 or newer, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate          # creates Thicket.xcodeproj
open Thicket.xcodeproj     # pick a simulator or your device, then Run
```

To run the automated checks:

```sh
swift test                 # logic tests (ThicketCore + ThicketKit); also runs on Linux
scripts/build.sh test      # swift test + the full suite on an iPhone simulator
scripts/build.sh device    # simulator build + unsigned arm64 device build -> build/Thicket-unsigned.ipa
scripts/build.sh           # all of the above
```

CI (`.github/workflows/ci.yml`) runs the logic tests on Linux. It also runs the simulator tests, the simulator build and the unsigned device build on a macOS runner, and uploads the unsigned `.ipa` as an artifact.

## Install on a device (sideloading)

**Get the .ipa:** the **Build IPA** workflow (`.github/workflows/ipa.yml`) builds an unsigned `Thicket.ipa` and attaches it to a GitHub Release:

- Latest build: https://github.com/anch-dev/Thicket/releases/download/latest/Thicket.ipa
- It rebuilds whenever app code is pushed. To build on demand, go to *Actions → Build IPA → Run workflow*. Pushing a `v*` tag (e.g. `v1.0`) creates a versioned release.

**Install it:** the .ipa is **unsigned**. Install it with a tool that signs it using your Apple ID:

- **AltStore / SideStore**: open the .ipa in the app (or use *My Apps → +*).
- **Sideloadly**: drag the .ipa in, enter your Apple ID, then click Start.

With a free Apple ID, the app expires after 7 days; refresh or reinstall it then. You may need to enable *Developer Mode* (Settings → Privacy & Security) and trust the profile (Settings → General → VPN & Device Management).

**Alternatively, build with Xcode:** open the project, choose your team under *Signing & Capabilities* on the **Thicket** target, and Run on a connected device. If your team requires it, change `PRODUCT_BUNDLE_IDENTIFIER` (`dev.anch.thicket`) in `project.yml`.

## Saving and lifecycle

- Campaign progress, best scores, best times, Endless records, lesson completion and settings are saved as versioned JSON in `UserDefaults`. Corrupt or newer data falls back to defaults instead of crashing.
- The game pauses automatically when the app goes inactive, for example on a call or the app switcher. Every held input is released at that point.
- When the app is backgrounded, the full round is snapshotted to Application Support. If iOS terminates the app, **Continue** on the title screen resumes exactly where you left off, paused.
- Audio uses the `.ambient` session category, so it respects the silent switch and mixes with other apps. The game has a single audio engine. It pauses on interruptions and in the background and resumes without duplicating playback. Volume and mute settings are in Settings and the pause menu.

## Rendering

The playfield, Pip and HUD are drawn in "art pixels": one cell is 16 px. The scene picks the largest **whole-number** device-pixel scale that fits inside the safe area, and all textures use nearest-neighbour filtering, so the art stays sharp and is never stretched. The touch controls sit in the outer thirds of the screen, inside the safe area and an extra margin away from the system edge-gesture zones.
