# Soft Form native design kit

Edit `tokens/soft-form.json`, then run `python3 scripts/generate-design-tokens.py` from the app root. Generated Swift lives in `Sources/SmoothWheelAppCore/DesignTokens.swift`; reusable controls are in `Sources/SmoothWheelAppCore/DesignSystem.swift`. The app uses system typography, dynamic semantic colors, and native macOS window controls. Brand resources are in `Resources/`.

The website is maintained separately. This repository builds and tests without website files or access to a private repository.

New feature designs must reuse this system in both the review mockup and implementation. Identify existing tokens and controls in the feature plan. Propose any missing shared pattern for review before adding it; avoid feature-local copies of colors, typography, spacing, or controls. Follow the [design approval workflow](../docs/IMPLEMENTATION.md).

The preset picker uses `DesignSurface`, `DesignButton`, a raised surface, 20-point semibold titles, 15-point system body text, and 12-point muted captions. Names and captions share a 12-point list inset, and choices are 28 points high. The picker uses 24-point outer spacing and a fixed footer with a scrolling list. The footer shows a text-only Save button and shows Manage presets when saved presets exist. A trailing SF Symbols checkmark marks the chosen row in both the picker and manager. A short muted underline beneath the name shows keyboard focus. The manager includes the active scrolling status in its accessible row name. The manager uses 15-point medium action labels beneath a 20-point semibold preset name, with semantic accent text for Delete. [Preset picker](../docs/screenshots/saved-presets.png) · [Manage presets](../docs/screenshots/manage-presets.png).

Ordinary buttons and settings tabs use the neutral track fill under the pointer. An inactive tab clears its fill on pointer exit. The selected tab retains its outline and returns to its raised fill on exit.

## Alerts

`DesignAlertPanel` pairs a raised 320-point surface with a 32-point symbol tile, 24-point insets, and two equal 44-point actions. Use a leading mint tile for a form and a centered accent-wash tile for a destructive confirmation. `DesignAlertTextField` shares one content rectangle between the native AppKit editor and the displayed value, so text stays vertically centered with a 12-point leading inset. Keep the label visible, and expand the panel for inline validation. The alert buttons share a 12-point radius and 8-point gap. Cancel uses the inset surface, confirmation uses the primary fill, and Delete uses accent text on accent wash.

Hover and press adjust the neutral or primary fill. On Delete they add an accent outline. Disabled actions use muted text on the raised surface. Keyboard focus uses the existing inner marker for buttons and the semantic focus outline for the active field. Increase Contrast strengthens control boundaries. Symbols are decorative, and text labels identify the actions. Put initial focus on Cancel for destructive confirmations, keep Escape available, and return focus to the originating action on cancellation. [Save dialog](../docs/screenshots/save-preset.png).

## Circular icon buttons

Use `DesignButton(circularIcon:label:discDiameter:)` for an icon-only action with a 44-point hit target. Back uses the default 36-point disc with `chevron.backward`. Close uses a compact 32-point disc with `xmark`, aligned with the bold Presets title. Pass a 14-point SF Symbol name and a label used for both accessibility and the tooltip. The disc uses `line` at rest and `track` on hover and press. Press and disabled states use muted ink. Increase Contrast adds a visible boundary. `PresetFocusButton` places its keyboard marker inside the disc.

## Motion

Use the 120 ms Fast token for fades and the 180 ms Normal token for switches and settling rows. A newly saved preset fades in at its final position over 180 ms. `SettingsMotion` fades passive outgoing views while the controller immediately commits the live view, input, and focus. Switches animate a confirmed state change and retarget from the displayed knob position on reversal. Reduce Motion resolves directly to the final state, including when macOS changes the preference during an animation. Native sheets, slider tracking, and the Playground document keep their native behavior. [Transition frame tests](../docs/TESTING.md#transition-frames)

The picker and preset dialogs use `PresetCard` to keep the raised background separate from the content. When one card replaces another, the outgoing background can finish fading after its text and controls have gone. Closing a single card fades its contents with its background.
