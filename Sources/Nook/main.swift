// Nook: pixel desktop windows, one per live Claude Code agent.
//
//   nook [--demo] [project-folder ...]
//
// Each folder opens an agent window running the user's own `claude` in that folder.
// --demo adds three scripted agents for tuning the window experience.

import AppKit

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory) // no Dock icon, never steals focus
app.run()
