# Soft Form native design kit

Edit `tokens/soft-form.json`, then run `python3 scripts/generate-design-tokens.py` from the app root. Generated Swift lives in `Sources/SmoothWheel/DesignTokens.swift`; reusable controls are in `Sources/SmoothWheel/DesignSystem.swift`. The app uses system typography, dynamic semantic colors, and native macOS window controls. Brand resources are in `Resources/`.

The website is maintained separately. This repository builds and tests without website files or access to a private repository.
