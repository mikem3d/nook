// Nook: pixel desktop windows, one per live Claude Code agent.
//
//   nook [--demo] [project-folder ...]
//   nook --engine-test <folder> --say=<text> [options]   (headless; see EngineTest.swift)
//
// Each folder opens an agent window running the user's own `claude` in that folder.
// --demo adds three scripted agents for tuning the window experience.

import AppKit

// Writing to an agent whose process just died must fail quietly, not kill Nook.
signal(SIGPIPE, SIG_IGN)

if CommandLine.arguments.contains("--engine-test") {
    EngineTest.run(Array(CommandLine.arguments.dropFirst()))
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory) // no Dock icon, never steals focus
app.run()
