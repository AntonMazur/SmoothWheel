# Release preparation

The public source repository is https://github.com/AntonMazur/SmoothWheel. Version 0.3.11 is an Apple Silicon build with an ad-hoc signature; publishing source does not make the app notarized.

Run `./scripts/test.sh`, `./build.sh`, and `./scripts/package-source.sh`. Validate the supported hardware, target apps, exclusions, shortcuts, sleep/wake, and permission changes. Verify the oldest supported macOS and build/test Intel separately before claiming support.

For a public binary release, use a stable Developer ID, hardened runtime, notarization, and stapling. Final signing requires the owner's Apple Developer identity. Upload the resulting ZIP as a GitHub Release asset and update the separately maintained website download together. No public binary release is created merely by pushing this repository.

## Homebrew distribution

The [developer-maintained tap](https://github.com/AntonMazur/homebrew-tap) installs the versioned GitHub release ZIP. For every release, update `version` and `sha256` in its `Casks/smoothwheel.rb` after verifying the uploaded asset. Keep existing release assets unchanged so installed casks remain reproducible. Validate the cask metadata and checksum, then check a fresh install and upgrade before updating installation claims.

Keep the architecture, minimum macOS, signing status, and first-launch caveats consistent with the actual artifact. The tap currently distributes the ad-hoc-signed v0.3.11 Apple Silicon build; Homebrew installation does not make it notarized. User steps are in [INSTALL.md](INSTALL.md).
