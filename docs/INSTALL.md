# Installing Nook

Nook is a menu-bar app for macOS that gives each of your Claude Code agents a small pixel window
in a corner of the screen.

**Nook does not talk to any API.** It has no API key and no account. Every agent window starts
*your* `claude` binary in a folder you pick and reads its output. So Claude Code has to be
installed on this Mac and logged in, or the windows will open and nothing will ever answer.

## Requirements

| | |
| --- | --- |
| macOS | 14 (Sonoma) or later, Apple silicon or Intel |
| Claude Code | installed and logged in — `claude --version` should work in a terminal |
| A Swift toolchain | Xcode, or Apple's Command Line Tools: `xcode-select --install` |
| Disk | about 1.5 GB while building; the installed app is a few MB |

If `claude` is missing:

    curl -fsSL https://claude.ai/install.sh | bash

then run `claude` once and sign in. Details: <https://docs.claude.com/en/docs/claude-code/setup>.

## Install

    curl -fsSL https://raw.githubusercontent.com/mikem3d/nook/main/scripts/install.sh | bash

That checks your macOS version, your toolchain and your `claude`, clones the repo to `~/.nook/src`,
builds the release configuration, assembles `Nook.app` and moves it into `/Applications`
(or `~/Applications` if `/Applications` is not writable). The first build takes a few minutes.

If you would rather read the script before running it — a good habit:

    git clone https://github.com/mikem3d/nook.git
    cd nook
    less scripts/install.sh
    ./scripts/install.sh

Run from inside a checkout, the installer builds *that* checkout and does not clone a second copy.

You can steer it:

| Variable | Meaning |
| --- | --- |
| `NOOK_SRC` | Where to keep the source (default `~/.nook/src`) |
| `NOOK_APP_DIR` | Where to put `Nook.app` (default `/Applications`, else `~/Applications`) |
| `NOOK_REF` | Branch or tag to build (default `main`) |
| `NOOK_YES=1` | Take every default, never wait for an answer |
| `NOOK_LAUNCH=0` | Do not offer to launch at the end |

### The manual route

The installer is only a wrapper around three commands:

    swift build -c release
    ./scripts/bundle.sh release        # produces dist/Nook.app
    ditto dist/Nook.app /Applications/Nook.app

## First run

Nook has no Dock icon. Two things appear:

- a **menu bar icon** (stacked windows) with *New Agent…*, *Settings…* and *Quit Nook*;
- a small **`+` orb** in a corner of your screen.

Click the `+` orb, choose a project folder, and an agent window docks in that corner. Click a
window to make it active: the others dim and an input bar appears at the bottom of the screen.

## The permission prompts, and why

macOS asks at the moment a feature is first used, not at install time. Nothing is asked for up
front, and declining any of these only disables that one feature.

| Prompt | When | Why |
| --- | --- | --- |
| **Microphone** | first time you hold the push-to-talk key (⌃⌥V) | To record while the key is down. Nothing is recorded otherwise. |
| **Speech Recognition** | same moment | To turn that recording into text. It happens on this Mac unless you explicitly turn on `nook.voice.allowNetwork`. |
| **Screen Recording** | first time you use "look at this" / a screen grab | Nook shells out to the system `screencapture` tool so you can hand an agent a picture of what you are looking at. macOS puts this under *Screen & System Audio Recording*; you have to grant it in System Settings and then relaunch Nook. |
| **Notifications** | first time an agent needs a decision while you are elsewhere | So a permission request or a finished turn reaches you when Nook's windows are not in front of you. Approve or deny straight from the notification. |

You can review or revoke all of them in **System Settings › Privacy & Security**.

## Gatekeeper: why building beats downloading

Nook is **not notarised** by Apple yet. What that means in practice depends entirely on how the
app got onto your Mac:

- **Built locally** (what the installer does) — the app has no quarantine attribute, so macOS
  opens it with no warning at all. This is the smooth path, and it is why the installer builds
  from source rather than downloading a binary.
- **Downloaded** (a release zip, from a browser) — macOS quarantines it. On recent versions the
  first double-click is refused outright and you have to go to **System Settings › Privacy &
  Security**, scroll to the bottom, and press **Open Anyway**, then confirm.

Once the project has a Developer ID certificate, `scripts/notarize.sh` produces a build with
neither problem.

## Updating

Run the installer again. It fetches the latest `main`, rebuilds, and replaces the installed app.
If Nook is running it offers to quit it first.

    curl -fsSL https://raw.githubusercontent.com/mikem3d/nook/main/scripts/install.sh | bash

Your agents, tasks and settings survive an update; they live outside the app bundle.

## Uninstalling

    ~/.nook/src/scripts/uninstall.sh

It removes `Nook.app`, then asks separately — defaulting to *keep* — about your data
(`~/Library/Application Support/Nook`: agents, tasks, schedules), your settings (the `dev.nook.app`
preferences domain) and the source checkout. Say no to all three and a reinstall picks up exactly
where you left off.

## Troubleshooting

**"Could not find the `claude` command"**, or a window opens and says so.
Nook looks on your `PATH` and then in `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin` and
`/usr/local/bin`. GUI apps do not inherit the `PATH` from your shell profile, so a `claude`
installed somewhere unusual can be invisible to Nook even though it works in your terminal.
Symlink it somewhere Nook looks:

    ln -s "$(which claude)" ~/.local/bin/claude

**Windows appear but agents never respond.**
Almost always Claude Code is installed but not signed in, or is out of quota. Check in a terminal:

    cd ~/some/project && claude -p "say hi"

If that fails or asks you to log in, fix it there first — Nook cannot log in for you. If it works,
start Nook from a terminal with logging on and watch what the agent process does:

    NOOK_LOG=1 /Applications/Nook.app/Contents/MacOS/Nook

**macOS asks for the microphone / screen recording again after every update.**
Expected, for now. Builds are signed *ad hoc*, and an ad-hoc signature is different on every
build, so macOS sees each update as a brand-new app and the permissions it remembered no longer
apply. A Developer ID signature is the only real fix; it is on the list.

**"Nook is damaged" or it will not open after downloading a release zip.**
That is quarantine, not damage. See *Gatekeeper* above, or install from source instead.

**The build fails with "no such module" or a Swift version error.**
Your toolchain is too old. Nook needs a Swift 6 toolchain (Xcode 16 or the matching Command Line
Tools). Check with `swift --version`, and if you have Xcode installed but unselected:
`sudo xcode-select -s /Applications/Xcode.app`.

**Where the logs are.**
Nook writes to standard error, and `open` sends that to the unified system log:

    log stream --predicate 'process == "Nook"' --info

For more detail, run the binary in a terminal with `NOOK_LOG=1` (above); it prints every agent
state change. Your data — agents, tasks, schedules, caches — is in
`~/Library/Application Support/Nook`; settings are in the `dev.nook.app` preferences domain
(`defaults read dev.nook.app`).
