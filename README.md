# QuickClose

A quiet macOS menu-bar utility for clearing your workspace in one click.

## Install

1. Open the [latest GitHub release](https://github.com/withLinda/QuickClose/releases/latest).
2. Download `QuickClose.dmg`.
3. Open the DMG and drag **QuickClose** to the **Applications** folder.
4. Launch QuickClose from Applications; it will appear in the menu bar.

The published release asset is named `QuickClose.dmg`; download that file from the
release page rather than the source-code archive. For command-line downloads, use
the latest release asset URL:

```sh
curl -L -o QuickClose.dmg https://github.com/withLinda/QuickClose/releases/latest/download/QuickClose.dmg
open QuickClose.dmg
```

The release DMG is signed and notarized for macOS. If macOS asks for confirmation the first time, choose **Open** in the security prompt.

## Behavior

- Click the menu-bar power icon to open the compact QuickClose panel.
- The compact panel grows only as large as the current app list needs, then becomes scrollable for larger lists.
- Each app row has its own quit button, and checked rows can be closed together with the primary action.
- The primary action follows the selected default: `Force Close` ends processes immediately, while `Normal Quit` gives apps a chance to save work.
- The panel grows from its compact size as apps appear and switches to scrolling when the list reaches the available screen height.
- Settings supports background-app grouping, protected music apps, deselection defaults, sorting, Finder/Trash extras, inactive-app auto-quit, launch at login, sounds, and the Force Close/Normal Quit picker.
- Normal Quit and Force Close requests remain pending until the target process disappears; refused or delayed requests are reported instead of being presented as completed.
- A short system sound confirms observed termination when sounds are enabled.
- The panel menu includes Settings, refresh, Help, background-app visibility, and `Quit` for exiting QuickClose itself.

QuickClose defaults to `NSRunningApplication.forceTerminate()` for the reference workflow. Choose `Normal Quit` when preserving unsaved work is more important; macOS may refuse a normal quit request or an app may remain open while it saves work.

## Build

```sh
xcodebuild -project QuickClose.xcodeproj -scheme QuickClose -configuration Debug build
xcodebuild -project QuickClose.xcodeproj -scheme QuickClose test
```

The project targets macOS 15 and uses SwiftUI, `MenuBarExtra`, native Settings, Swift 6 strict concurrency, and injected model dependencies for quit-routing tests.
