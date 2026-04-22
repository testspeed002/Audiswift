import AppKit
import SwiftUI
import MediaPlayer

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

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
        window?.minSize = NSSize(width: 720, height: 480)
        window?.setFrameAutosaveName("AudiswiftMainWindow")
        window?.contentView = NSHostingView(rootView: contentView)
        window?.makeKeyAndOrderFront(nil)

        // Setup menu bar and keyboard shortcuts
        setupMenuBar()

        // Restore playback state from last session
        Task {
            await AudioPlayerManager.shared.restorePlaybackState()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
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

    @objc private func showPreferences() {
        // TODO: Show preferences window
        print("Preferences not yet implemented")
    }
}
