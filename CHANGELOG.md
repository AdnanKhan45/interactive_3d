## 2.5.0

* 19th release of `interactive_3d`: **Unselectable Parts** 🚫
- New `unselectableEntities` widget param: taps on the parts you list do nothing on Android and iOS, with no highlight flash and no selection event. They can still be selected from code.
- Android memory fix: selection and cache highlights no longer stay in memory until the model closes, so long tapping sessions stop growing memory.
- Try it out from the **Tap to select** page in the example app, where the jaws are unselectable.

## 2.4.0

* 18th release of `interactive_3d`: **Steadier Android and Rejected Taps** 🛠️
- New `onSelectionRejected(name)` callback on both platforms: find out which part a `selectionSequence` refused, so you can tell the user why nothing happened.
- Android crash fixes: no more crash when a view closes, reopens, or resets while a part shows a material override or texture, when a view closes during or right after loading, or on Android 9 and older.
- Android now handles rotation and layout changes (the model keeps its shape and taps hit the right part), starts at `defaultZoom` without a flash at zoom 1.0, and keeps drawing until the latest change is on screen on slow GPUs.
- Android lighting: `iblPath` and `skyboxPath` now each work on their own, and glow from the model file or an `emissive` override is no longer wiped when lighting loads. Overrides, preselection, and cache colors now hold on every part of large models.
- Try it out from the example app, especially **Selection order**, which now shows rejected taps, and **Materials and textures**.

## 2.3.0

* 17th release of `interactive_3d`: **Camera Controls and Reliable Loading** 🎥
- New controller methods `resetCamera()` and `zoomBy(delta)` for your own reset and zoom buttons. `zoomBy` steps from the live zoom, so it stays correct after a pinch.
- Zoom now works on iOS: `defaultZoom` and `setCameraZoomLevel` frame the model the same way on Android and iOS. iOS apps that never set `defaultZoom` keep their current starting view.
- New `onModelLoaded`, `onModelLoadError`, and `errorBuilder`. `loadingWidget` now stays up until the model is drawn, on both platforms; it used to disappear early on Android and never showed on iOS.
- Fixes: Android reported a load as finished too early, could lose a load requested before its surface was ready, crashed on load errors, and drew late loads and zoom changes only after a touch. Multi-file `.gltf` models now load on iOS. Apps no longer bundle the plugin's README images or 3.5 MB of unused lighting files.
- Try it out from the reorganized example app, especially the **Camera** and **Load from a URL** pages. The README is rewritten with new recordings.

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
