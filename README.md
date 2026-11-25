# QuickClose

A quiet macOS menu-bar utility for clearing your workspace in one click.

[Slipway app icon and editable design files](Docs/AppIcon/README.md)

## Install or update from the DMG

**[Download the latest QuickClose.dmg](https://github.com/withLinda/QuickClose/releases/latest/download/QuickClose.dmg)** · [What’s new in 1.1.1](https://github.com/withLinda/QuickClose/releases/tag/v1.1.1)

QuickClose 1.1.1 (build 4) supports Apple silicon and Intel Macs running macOS 15 or later. The repository is private: sign in to GitHub with an account that has access before opening the download link.

1. **If updating:** open QuickClose’s menu-bar panel and choose **Quit** from the footer menu. **Quit All** quits selected apps, not QuickClose itself.
2. Open the downloaded `QuickClose.dmg`. Drag **QuickClose.app** onto **Applications** in the installer window. Choose **Replace** if Finder asks.
3. Eject the **QuickClose** disk image. In **Applications**, open **QuickClose** with the peach **Q** icon. Click the **power symbol** in the menu bar to use it.

The DMG is signed and notarized. If macOS asks whether to open the downloaded app on first launch, choose **Open**.

From Terminal, use the [GitHub CLI](https://cli.github.com/) signed in to the same account. Run these commands in a folder that does not already contain `QuickClose.dmg`:

```sh
gh release download --repo withLinda/QuickClose --pattern QuickClose.dmg
open QuickClose.dmg
```

## Behavior

- Click the menu-bar power icon to open the compact QuickClose panel.
- The compact panel grows only as large as the current app list needs, then becomes scrollable for larger lists.
- Each app row has its own quit button, and checked rows can be closed together with the primary action.
- **Quit All** (⌘⌥Q) asks the checked apps in the current list to quit normally, giving them a chance to save work.
- If an app refuses or stays open after eight seconds, check it for a save prompt. A separate footer button, such as **Force Quit Sketch** or **Force Quit 3 Remaining Apps**, applies only to apps from that attempt that are still open, visible, and checked. Force Quit can discard unsaved changes.
- Individual row buttons default to **Quit**. The **Row action** setting can switch them to **Force Quit**. An existing quit-mode preference is kept for those buttons only. Idle quitting always uses a normal quit.
- Settings also supports background-app grouping, protected music apps, deselection defaults, sorting, Finder/Trash extras, inactive-app auto-quit, launch at login, and sounds.
- A short system sound confirms observed termination when sounds are enabled.
- The panel menu includes Settings, refresh, Help, background-app visibility, and `Quit` for exiting QuickClose itself.

## Build

```sh
xcodebuild -project QuickClose.xcodeproj -scheme QuickClose -configuration Debug build
xcodebuild -project QuickClose.xcodeproj -scheme QuickClose test
```

The project targets macOS 15 and uses SwiftUI, `MenuBarExtra`, native Settings, Swift 6 strict concurrency, and injected model dependencies for quit-routing tests.
