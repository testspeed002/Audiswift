import AppKit
import SwiftUI
import MediaPlayer

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow?
    private var preferencesWindow: NSWindow?

    // Hard floor for the main window. Used by both the contentMinSize/minSize
    // initial setup AND the windowWillResize delegate clamp, so neither tiling,
    // un-tiling, nor restored autosaved frames can shrink the window past it.
    private let windowFloor = NSSize(width: 480, height: 480)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView()
            .environmentObject(AudioPlayerManager.shared)
            .environmentObject(LibraryViewModel.shared)
            .environmentObject(ThemeManager.shared)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window?.title = "Audiswift"
        window?.titlebarAppearsTransparent = true
        window?.toolbarStyle = .unified
        window?.center()
        window?.setFrameAutosaveName("AudiswiftMainWindow")
        window?.isReleasedWhenClosed = false
        window?.contentView = NSHostingView(rootView: contentView)

        // Enforce a 480×480 floor on the CONTENT area. With
        // .fullSizeContentView the title bar overlays the content, so
        // `minSize` alone isn't always enough — `contentMinSize` is what
        // AppKit actually clamps the live-resize loop against. Set this
        // AFTER the hosting view is in place so the hosting view's
        // intrinsic content size can't shrink the window below it.
        window?.contentMinSize = windowFloor
        window?.minSize = windowFloor
        // Become the window's delegate so `windowWillResize` can clamp
        // tiled-untiled and programmatic resizes that bypass minSize.
        window?.delegate = self
        // If a previous session autosaved a smaller frame, bump it back up.
        if let w = window, w.frame.size.width < windowFloor.width || w.frame.size.height < windowFloor.height {
            var frame = w.frame
            frame.size.width = max(frame.size.width, windowFloor.width)
            frame.size.height = max(frame.size.height, windowFloor.height)
            w.setFrame(frame, display: true, animate: false)
        }

        window?.makeKeyAndOrderFront(nil)

        // Setup menu bar and keyboard shortcuts
        setupMenuBar()

        // Restore playback state from last session
        Task {
            await AudioPlayerManager.shared.restorePlaybackState()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // Fallback path for OAuth callbacks delivered via the custom URL scheme
    // (e.g. when ASWebAuthenticationSession doesn't intercept the redirect and
    // macOS routes `audiswift://oauth?code=…` to the app directly).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "audiswift" {
            AudiusAuth.shared.handleIncomingURL(url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // MARK: - NSWindowDelegate

    /// Clamp every resize attempt (drag, tiling un-tile, programmatic) to the
    /// 480×480 floor. `minSize`/`contentMinSize` alone don't catch the
    /// "untiledFrame restored" path on macOS, which is how the window was
    /// previously shrinking to ~87×52 after being tiled.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(frameSize.width, windowFloor.width),
               height: max(frameSize.height, windowFloor.height))
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Save playback state before quitting
        AudioPlayerManager.shared.savePlaybackState()
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        // Main Menu
        let mainMenu = NSMenu()

        // Audiswift Menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Audiswift", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Audiswift", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File Menu
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit Menu
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Playback Menu
        let playbackMenu = NSMenu(title: "Playback")

        let playPauseItem = NSMenuItem(title: "Play/Pause", action: #selector(togglePlayPause), keyEquivalent: " ")
        playPauseItem.keyEquivalentModifierMask = []
        playbackMenu.addItem(playPauseItem)

        let nextItem = NSMenuItem(title: "Next Track", action: #selector(playNext), keyEquivalent: "\u{F703}") // Right arrow
        nextItem.keyEquivalentModifierMask = [.command]
        playbackMenu.addItem(nextItem)

        let prevItem = NSMenuItem(title: "Previous Track", action: #selector(playPrevious), keyEquivalent: "\u{F702}") // Left arrow
        prevItem.keyEquivalentModifierMask = [.command]
        playbackMenu.addItem(prevItem)

        playbackMenu.addItem(NSMenuItem.separator())

        let seekForwardItem = NSMenuItem(title: "Seek Forward", action: #selector(seekForward), keyEquivalent: "\u{F703}") // Right arrow
        seekForwardItem.keyEquivalentModifierMask = []
        playbackMenu.addItem(seekForwardItem)

        let seekBackwardItem = NSMenuItem(title: "Seek Backward", action: #selector(seekBackward), keyEquivalent: "\u{F702}") // Left arrow
        seekBackwardItem.keyEquivalentModifierMask = []
        playbackMenu.addItem(seekBackwardItem)

        playbackMenu.addItem(NSMenuItem.separator())

        let volUpItem = NSMenuItem(title: "Volume Up", action: #selector(volumeUp), keyEquivalent: "\u{F700}") // Up arrow
        volUpItem.keyEquivalentModifierMask = [.command]
        playbackMenu.addItem(volUpItem)

        let volDownItem = NSMenuItem(title: "Volume Down", action: #selector(volumeDown), keyEquivalent: "\u{F701}") // Down arrow
        volDownItem.keyEquivalentModifierMask = [.command]
        playbackMenu.addItem(volDownItem)

        playbackMenu.addItem(NSMenuItem.separator())

        playbackMenu.addItem(withTitle: "Toggle Shuffle", action: #selector(toggleShuffle), keyEquivalent: "s")
        playbackMenu.addItem(withTitle: "Cycle Repeat Mode", action: #selector(cycleRepeat), keyEquivalent: "r")

        let playbackMenuItem = NSMenuItem()
        playbackMenuItem.submenu = playbackMenu
        mainMenu.addItem(playbackMenuItem)

        // Window Menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Show All Windows", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // Help Menu
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Audiswift Help", action: nil, keyEquivalent: "")
        let helpMenuItem = NSMenuItem()
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    // MARK: - Playback Actions

    @objc @MainActor private func togglePlayPause() {
        AudioPlayerManager.shared.togglePlayPause()
    }

    @objc @MainActor private func playNext() {
        AudioPlayerManager.shared.playNext()
    }

    @objc @MainActor private func playPrevious() {
        AudioPlayerManager.shared.playPrevious()
    }

    @objc @MainActor private func seekForward() {
        AudioPlayerManager.shared.seekForward(10)
    }

    @objc @MainActor private func seekBackward() {
        AudioPlayerManager.shared.seekBackward(10)
    }

    @objc @MainActor private func volumeUp() {
        let newVolume = min(AudioPlayerManager.shared.volume + 0.1, 1.0)
        AudioPlayerManager.shared.volume = Float(newVolume)
    }

    @objc @MainActor private func volumeDown() {
        let newVolume = max(AudioPlayerManager.shared.volume - 0.1, 0.0)
        AudioPlayerManager.shared.volume = Float(newVolume)
    }

    @objc @MainActor private func toggleShuffle() {
        AudioPlayerManager.shared.toggleShuffle()
    }

    @objc @MainActor private func cycleRepeat() {
        AudioPlayerManager.shared.cycleRepeat()
    }

    @objc @MainActor func showPreferences() {
        if let existing = preferencesWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let prefs = PreferencesView()
            .environmentObject(ThemeManager.shared)

        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Preferences"
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: prefs)
        panel.makeKeyAndOrderFront(nil)
        preferencesWindow = panel
    }
}
