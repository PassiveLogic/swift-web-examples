import ElementaryUI

// Connect Dispatch to the page before any work is queued.
installScheduler()

Application(AppView()).mount(in: "#app")
