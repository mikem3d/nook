# Nook

Pixel desktop windows for macOS, one per live Claude Code agent. Native AppKit + SpriteKit,
built with SwiftPM, macOS 14 or later. Each window runs your own unmodified `claude` in a
project folder.

## Build and test

    swift build
    swift test

## Run

    scripts/run.sh --demo                      # three scripted agents, spends no usage
    scripts/run.sh ~/work/project-a ~/work/b   # one real agent per folder

`scripts/run.sh` bundles `dist/Nook.app` and opens it; arguments pass through. `swift run Nook …`
also works for everything except voice: macOS kills a process that asks for the microphone
without the usage strings in the bundle's Info.plist, so outside the bundle Nook refuses to ask.

| Flag or variable | Effect |
| --- | --- |
| `--demo` | Adds three scripted agents for tuning the window experience. |
| `<folder> …` | Opens an agent running `claude` in each folder. |
| `--say=<text>` | Sends an opening message to every real agent (engine smoke test). |
| `NOOK_LOG=1` | Prints every agent state change to stderr. |
| `NOOK_CONFIG=debug` | Makes `scripts/run.sh` build the debug configuration. |

`open` sends output to the system log. To see `NOOK_LOG` output, start the bundled binary directly:

    NOOK_LOG=1 dist/Nook.app/Contents/MacOS/Nook --demo

## Bundle

    scripts/bundle.sh [debug|release]     # default release -> dist/Nook.app

Builds, copies the binary and the SwiftPM resource bundle (`Contents/Resources/Nook_Nook.bundle`),
fills `Support/Info.plist` with the version from `VERSION`, draws the placeholder icon
(`scripts/make_icon.swift`), and signs ad-hoc with the hardened runtime and
`Support/Nook.entitlements` (microphone only). `NOOK_BUNDLE_ID` overrides the placeholder
identifier `dev.nook.app`; `NOOK_SIGN_ID` signs with a real identity.

An ad-hoc signature changes with every build, so macOS may ask for microphone and speech access
again after a rebuild. A stable signing identity avoids that.

`scripts/notarize.sh` does Developer ID signing, notarisation and stapling for distribution; its
header explains the one-time setup and the environment variables it needs.

## Voice

Hold **⌃⌥V**, speak, release to send. Transcription happens on this Mac.

- "sternfall, run the tests" goes to the agent named sternfall, without focusing it. Names may be
  split ("zip demand …") and long names forgive one slip; anything less certain is not treated as
  a name.
- "everyone, …" or "all agents, …" goes to every agent.
- Anything else goes to the active agent, or the last one you used.
- "allow", "approve" or "deny" on its own answers the active agent's pending permission;
  "sternfall, allow" answers sternfall's.

| Preference (`defaults write dev.nook.app …`) | Meaning |
| --- | --- |
| `nook.hotkey.voice -string "control+option+v"` | The talk key: modifiers and one key joined by `+`. |
| `nook.voice.allowNetwork -bool true` | Allow Apple's servers when the language has no on-device model. Off by default. |
| `nook.voice.locale -string en-GB` | Recognition language; defaults to the system's. |
| `nook.voice.aliases -dict asche-kron '("ash crown")'` | Extra spoken names for labels the recogniser mangles. |
