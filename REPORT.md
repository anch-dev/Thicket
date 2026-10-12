# Thicket: delivery report

## What was built

- **ThicketCore**: the pure-Swift rules engine. It has no UIKit, SpriteKit or AVFoundation imports.
  - Board model and line finder for horizontal, vertical and both diagonal directions. A line needs a Seed; three Mites alone never match.
  - Resolver for overlapping and simultaneous lines, Starseed creation and its color clear, and the Slant, Shifter and Flicker Mites.
  - Structural gravity: anything that loses support becomes a "Faller".
  - Chain tagging and scoring multipliers.
  - Pip's moves: walk, turn, step up/down, climb the side of a stack, climb down, lift the whole stack, pull one piece, place, kick, catch.
  - Input buffering (8 ticks).
  - Wren/Gloom phase cycle, Canopy slam and lift. Chains shorten the Gloom phase.
  - Crush, overflow and trapped losses.
  - 99 campaign round configs, Endless, Time Trial trails, 8 lessons, and 2-player Versus with Mite attacks.
  - Seeded SplitMix64 RNG and a fixed 60 Hz `step`. The whole state is `Codable`.
- **ThicketKit**: pure-Swift support code.
  - D-pad sector geometry and a multitouch tracker (finger ownership, rolling, latched taps, reset/sync against stuck input).
  - Input merger and edge detector; keyboard maps using USB HID codes.
  - Control layouts saved per device class.
  - Versioned persistence that tolerates corrupt data; the session/mode flow model.
  - Chiptune synth with three original songs and 27 procedural sound effects.
  - Generated pixel-art sprite data.
- **iOS app**:
  - SpriteKit renderer with integer pixel scaling, nearest filtering and safe-area-aware layout. Effects include clear pops, score pop-ups, chain and phase banners, the Starseed flash and a slam shake.
  - UIKit multitouch control overlay with haptics and an edit mode.
  - GameController controllers and hardware keyboard: polled every tick, with change handlers latching short taps.
  - AVAudioEngine with one source node, the `.ambient` category and interruption handling.
  - SwiftUI menus: title, rounds, time trial, lessons, settings, control editor, pause and results.
  - Auto-pause, background snapshot and **Continue** after termination.
- **Build tooling**: XcodeGen `project.yml` (iOS 16+, iPhone + iPad, landscape, arm64 device build), `scripts/build.sh`, and a GitHub Actions workflow with a Linux logic job and a macOS build/test/screenshot job.
- **Art and audio**: all original. The sprites are authored as text in `scripts/sprites.py`, which also generates the app icon. The music and sound effects are synthesized from note data written for this project.

## Test results

- **SwiftPM, Linux (local, Swift 6.0.3):** 111 tests, 0 failures. ThicketCore has 74 tests, ThicketKit 37.
- **SwiftPM, macOS CI runner:** 111 tests, 0 failures.
- **Xcode on an iOS 26.2 simulator (iPhone SE 3rd gen), CI:** 116 tests, 0 failures. These are the 111 above plus 5 app-layer tests:
  - UserDefaults store
  - nearest-filtered textures
  - whole-number scene pixel scale
  - touch view setup
  - audio mixer output
- **Builds, CI:** the simulator app build succeeded. The unsigned Release build for arm64 devices succeeded; the binary is `Mach-O 64-bit executable arm64`. The unsigned `.ipa` is uploaded as a CI artifact.

The required test areas are covered, including:

- each line direction, the "no three-Mite match" rule and the Seed requirement
- overlapping and simultaneous lines
- Starseed creation and its color clear
- each Mite type
- gravity, and 2- and 3-step chains
- lifting, pulling and placing stacks; kicks stopping at a wall or a piece
- climbing limits
- carried pieces while the board resolves
- Canopy slam, crush, overflow and trapped
- round progression, scoring and multipliers
- deterministic replay and snapshot resume
- buffering
- D-pad sectors, multitouch merge and stuck-input prevention
- persistence
- every lesson being completable with a scripted input

## Verified vs. not verified

**Verified:**

- The logic modules compile and pass on Linux and macOS.
- The full iOS project compiles for the simulator and for arm64 devices with a current Xcode on GitHub's macOS runner.
- The test suite passes on an iOS simulator.
- The app launches on the simulator, and CI captures screenshots of it (see the `ci-screenshots` branch).

**Not verified:**

- **No testing on a physical device.** The device build is unsigned and has not been installed or run on hardware.
- Real multitouch feel, haptics and game controller / keyboard input on hardware.
- Audio output through speakers, silent-switch behaviour and interruption recovery on a device.
- Long play sessions and difficulty tuning by a human. Balance was checked only with an idle-player simulation: survival is about 2 min in round 1 and about 14 s in round 99. No human or bot has played a full round to completion.
- iPad Versus with two physical controllers.

## Notes and decisions

- Rules the brief left open were settled in code and are documented in `README.md`:
  - A maximal same-color run clears entirely if it contains a Seed.
  - Slant Mites break non-diagonal lines.
  - A piece in two lines at once is hit once.
  - Wren avoids dropping on Pip, and she pushes the Canopy up a row when she returns.
  - A piece landing on Pip's head ends the round, but one landing on a load he is carrying is caught.
  - Spawns avoid columns that would instantly overflow.
- Pip cannot climb while carrying. With climbing allowed elsewhere, "trapped" mostly happens when Pip is in a pit holding a load that he cannot set down.

## Next steps to try it on a device

1. On a Mac with Xcode 15.4 or newer, run `brew install xcodegen && xcodegen generate && open Thicket.xcodeproj`.
2. Select your team under *Signing & Capabilities*. If needed, change the bundle id `dev.anch.thicket`.
3. Run on a connected iPhone or iPad. Alternatively, re-sign the CI `.ipa` with AltStore, SideStore or Sideloadly.
