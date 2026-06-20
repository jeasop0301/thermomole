import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI
import ThermoMoleCore
import ThermoMoleNative
import UniformTypeIdentifiers

@main
enum ThermoMoleMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        let windowed = ProcessInfo.processInfo.environment["THERMOMOLE_WINDOWED"] == "1"
        let showsDockIcon = windowed || UserDefaults.standard.bool(forKey: "showsDockIcon")
        app.setActivationPolicy(showsDockIcon ? .regular : .accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var mainWindow: NSWindow?
    private var freshnessTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    /// True only in THERMOMOLE_SNAPSHOT render mode — keeps the dev hook side-effect-free
    /// (don't flush accumulated exposure/strain back over the user's real history on exit).
    private var isSnapshotMode = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dev hook: render the menu-bar card to a PNG and quit (for sharing screenshots).
        if let snapPath = ProcessInfo.processInfo.environment["THERMOMOLE_SNAPSHOT"] {
            runSnapshotMode(path: snapPath)
            return
        }

        setupStatusItem()
        setupPopover()

        Publishers.CombineLatest(model.$snapshot, model.$menuBarMetrics)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot, metrics in
                self?.updateMenuBar(snapshot, metrics: metrics)
            }
            .store(in: &cancellables)

        model.start()
        startMenuBarFreshnessTimer()

        if ProcessInfo.processInfo.environment["THERMOMOLE_WINDOWED"] == "1" {
            showMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        freshnessTimer?.invalidate()
        // Snapshot mode is a throwaway render run — never write its samples to disk.
        guard !isSnapshotMode else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached { [model] in
            await model.flushExposureForTermination()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }

    /// Renders the popover card to a PNG (dark appearance, @2x) then terminates.
    /// Invoked via THERMOMOLE_SNAPSHOT=<path>. Waits briefly so the model loads
    /// persisted history and takes a first live sample before rendering.
    private func runSnapshotMode(path: String) {
        isSnapshotMode = true
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        model.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.captureSnapshot(to: path)
            NSApp.terminate(nil)
        }
    }

    @MainActor
    private func captureSnapshot(to path: String) {
        // THERMOMOLE_SNAPSHOT_VIEW=window renders the main window (Status/Settings, tab via
        // THERMOMOLE_TAB); default renders the menu-bar popover card.
        let content: AnyView
        if ProcessInfo.processInfo.environment["THERMOMOLE_SNAPSHOT_VIEW"] == "window" {
            content = AnyView(MainWindowView(model: model)
                .frame(width: 1040, height: 720)
                .environment(\.colorScheme, .dark))
        } else {
            content = AnyView(MenuBarPopoverView(model: model) {}
                .environment(\.colorScheme, .dark))
        }
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        var image: NSImage?
        let dark = NSAppearance(named: .darkAqua)!
        dark.performAsCurrentDrawingAppearance {
            image = renderer.nsImage
        }
        guard let image,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.title = "CPU --° · BAT --° · RAM --%"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Patina"
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        let hosting = NSHostingController(
            rootView: MenuBarPopoverView(model: model) { [weak self] in
                self?.showMainWindow()
            }
        )
        // Size the popover to the SwiftUI content (the Patina card is 424 wide with
        // intrinsic height) so the box hugs the card and the arrow stays aligned.
        hosting.sizingOptions = [.preferredContentSize]
        // The card is Dark Jewel only — pin the host appearance so thermoAdaptive resolves
        // dark even when the system is in Light mode (mirrors the snapshot path).
        hosting.view.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = hosting
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem?.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            // Activate + make the popover window key so a transient popover from an
            // .accessory (menu-bar-only) app reliably dismisses on an outside click.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Patina", action: #selector(openMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Patina", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openMainWindow() {
        showMainWindow()
    }

    @objc private func refreshNow() {
        model.refresh()
        updateMenuBar(model.snapshot, metrics: model.menuBarMetrics)
    }

    private func startMenuBarFreshnessTimer() {
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updateMenuBar(self.model.snapshot, metrics: self.model.menuBarMetrics)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        freshnessTimer = timer
    }

    private func showMainWindow() {
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Patina"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: MainWindowView(model: model)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow = window
    }

    private func updateMenuBar(_ snapshot: SystemSnapshot, metrics: [MenuBarMetric]) {
        guard let button = statusItem?.button else { return }
        let condition = systemCondition(for: snapshot)
        let presentation = MenuBarPresentation(snapshot: snapshot, metrics: metrics)
        let prefixColor = presentation.freshnessLevel == .stale ? NSColor.systemRed : nsColor(for: condition)

        let attributed = NSMutableAttributedString(string: presentation.visibleTitle)
        attributed.addAttribute(.foregroundColor, value: prefixColor, range: NSRange(location: 0, length: 1))

        let level = snapshot.thermal.batteryWarningLevel
        if presentation.freshnessLevel != .stale, level != .normal, let segment = presentation.batterySegment {
            let prefixLength = (presentation.visibleTitle as NSString).length - (presentation.title as NSString).length
            let tintRange = NSRange(location: segment.range.location + prefixLength, length: segment.range.length)
            if NSMaxRange(tintRange) <= attributed.length {
                attributed.addAttribute(
                    .foregroundColor,
                    value: nsColor(for: SystemConditionPolicy.batteryTint(for: level)),
                    range: tintRange
                )
            }
        }

        if level == .hot, snapshot.battery.isOnACPower {
            let attachment = NSTextAttachment()
            attachment.image = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "charging while hot")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
            attachment.bounds = NSRect(x: 0, y: -2, width: 12, height: 12)
            attributed.insert(NSAttributedString(string: " "), at: 0)
            attributed.insert(NSAttributedString(attachment: attachment), at: 0)
        }

        button.attributedTitle = attributed
        button.toolTip = presentation.toolTip
        if level == .hot, snapshot.battery.isOnACPower {
            button.setAccessibilityLabel("Charging while hot. " + presentation.accessibilityLabel)
        } else {
            button.setAccessibilityLabel(presentation.accessibilityLabel)
        }
    }
}










