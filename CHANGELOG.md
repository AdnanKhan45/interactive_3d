## 2.2.0

* 16th release of `interactive_3d`: **Runtime Base Color Textures** 🖼️
- New controller API `setEntityTexture(name, bytes)` to upload a PNG or JPEG onto any entity at runtime, decoded natively. An active color override tints the uploaded texture.
- `resetEntityTexture(name)` removes a texture while keeping any color/metallic/roughness override; `resetAllEntityTextures()` clears them all.
- New widget param `initialEntityTextures` to apply textures on model load, mirroring `initialMaterialOverrides`.
- Textures merge into the same per-entity override as color and PBR factors and ride the selection precedence stack. The mesh must have UV coordinates; images larger than 2048px are downsampled.
- Try it out from the **PBR Override Testbed** page in the example app.

## 2.1.1

* 15th release of `interactive_3d`: **Flutter 3.44 Compatibility** 🛠️
- Added Swift Package Manager support alongside the existing CocoaPods podspec. iOS sources moved to `ios/interactive_3d/Sources/interactive_3d/`.
- Migrated Android to Built-in Kotlin. Removed `apply plugin: "kotlin-android"`, the manual KGP classpath, and the legacy `kotlinOptions` block; replaced with a top-level `kotlin { compilerOptions { } }` block. Future Flutter releases reject plugins that apply KGP manually.
- Minimum Flutter version bumped to `3.44.0`. Stay on `2.1.0` if you are on an older Flutter SDK.

## 2.1.0

* 14th release of `interactive_3d`: **Runtime PBR Material Overrides** 🎨
- New controller API to change color, metallic, roughness, and emissive on any entity at runtime. GLB textures are preserved, the color tints them.
- New widget param `initialMaterialOverrides` to apply overrides on model load. Pair it with your own state layer for persistence.
- Fixed a controller race where rebuilding `Interactive3d` with a new key could leave the controller detached.
- Try it out from the new **PBR Override Testbed** page in the example app.

## 2.0.4

* 13th release of `interactive_3d`
- Added `selectionSequence` enforcement on Android, matching the existing iOS behavior. Taps that violate the configured order are rejected and emit a `selectionRejected` event.


## 2.0.3

* 12th release of `interactive_3d`
- Adaptive render resolution using capped devicePixelRatio for sharper output without Hybrid Composition performance cost.
- Fixed touch coordinate scaling to match render buffer dimensions.
- Removed redundant native-side supersampling.

## 2.0.2

* 11th release of `interactive_3d` 
- Small fixes and optimizations for Android and iOS platforms.

## 2.0.1

* 10th release of `interactive_3d` — **Bug Fix & Code Quality Release** 🛠️
- Fixed selection clear, cache clear, refresh cache, and visibility toggle not working correctly on Android.
- Fixed cache clear not preserving active selection color on iOS.
- Codebase reorganized into focused files across all platforms — no API changes.

## 2.0.0

* 9th release of `interactive_3d` — **Major Release** 🚀
- **BREAKING CHANGE:**
  - Android rendering migrated from Hybrid Composition (AndroidView) to **Texture API (SurfaceProducer)** — dramatically improved performance and instant tap response.
  - iOS memory management optimized to prevent leaks and crashes.

- **New Feature (Both Platforms):**
  - `solidBackgroundColor` — use a solid color background instead of IBL skybox while keeping IBL lighting for PBR quality.

## 1.2.4

* 8th release of `interactive_3d`.
- Feature:
    - Android Memory Performance Optimized

## 1.2.3

* 7th release of `interactive_3d`.
- Feature:
    - Android & iOS memory leaks lead to crash fixes
    - Performance Optimized on Android
    - Example UI updates

## 1.2.2

* 6th release of `interactive_3d`.
- Feature:
  - Control Visibility of different parts of model using Interactive3dController.

## 1.2.1

* 5th release of `interactive_3d`.
- Fix:
  - iOS Plugin name conflict issue fix.
- Feature:
  - Load background environment for iOS.

## 1.2.0

* 4th release of `interactive_3d`.
- Features:
  - Patch Colors (update selected & preselected colors).
  - Interactive3dController introduced.
  - iOS Support with all features on Android 🚀

## 1.0.1

* 3rd release of `interactive_3d`.
- Features:
  - Preselection based on entity names.
  - Dynamic selected color.
  - Set Default Zoom.
  - Load model and background environments from network URLs.

## 0.0.2

* 2nd release of `interactive_3d`.
- Features:
    - App lifecycle crash fixed.
    - Load models background environments ibl and skybox `.ktx` files fix.
    - Code refactored.

## 0.0.1

* Initial release of `interactive_3d`.
- Features:
    - Render `.glb` and `.gltf` models.
    - Interactive touch gestures to extract information.
    - Currently supports only Android using the Filament Engine.
    - Open-source and customizable.
