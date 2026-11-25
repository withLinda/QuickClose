# Slipway · QuickClose app icon

[Sketch source](Slipway.sketch) · [Layered SVG](Slipway.svg) · [Icon Composer document](../../Resources/Slipway.icon) · [Default macOS PNG](Slipway-macOS.png)

The Sketch master contains two editable layers: the full-bleed slate background (`#232A2E`) and the peach Q (`#E69875`). The letter is a compound Bézier shape, not a font. The notch and counter expose the background. On the 1024 px canvas the vector mark occupies x 208–831, y 203–892 (exclusive upper bounds), with 98.6% silhouette intersection-over-union against the approved concept.

In Composer the slate is the root fill. The [exported Q](layers/01_slipway-q.svg) sits above it at 100% scale without an offset. The face is opaque, without shadows or refraction; the system supplies the edge highlight. Dark appearance adapts the background. Mono uses a white face so the Q retains more contrast when the system applies a tint.

QuickClose’s app target selects `Slipway` in `project.yml`. To update the shape, edit the Sketch master, export the transparent Q on its original 1024 px canvas, then replace the image in Composer. Keep the layer SVG and the Composer asset in sync.

## Verification · 2026-11-26

- The layer audit passed with zero errors or warnings. The foreground SVG in the saved icon is byte-identical to the Sketch export.
- The six [macOS appearances](appearances.png) were rendered at 1024 and 64 px. On the default 1024 px export, the face and counter sampled `#E69875` and `#23292D` after ICC conversion to sRGB (6.39:1 contrast). These are interior samples, not a guarantee across tints and wallpapers.
- Xcode 27.2’s Release build contains `CFBundleIconName = Slipway`, compiled assets, and `Slipway.icns`. The fallback decoded through `iconutil`; it was not tested on a separate macOS 15 device.
- macOS resolved the icon directly from the built application through `NSWorkspace`. [See QuickClose between Calculator and Notes at 64 and 32 px](workspace-neighbors.png).
