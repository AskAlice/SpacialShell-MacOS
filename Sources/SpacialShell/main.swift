import AppKit

// An accessory app: no dock icon, no menu bar, one long-lived run loop. `NSApplication.delegate`
// is unowned, so `runtime` has to be a top-level binding — it must outlive `app.run()`.
let app = NSApplication.shared
let runtime = AppRuntime()
app.delegate = runtime
app.run()
