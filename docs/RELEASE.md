# Release preparation

The public source repository is https://github.com/AntonMazur/SmoothWheel. Version 0.3.11 remains a local Apple Silicon prototype with an ad-hoc signature; publishing source does not make the app notarized.

Run `./scripts/test.sh`, `./build.sh`, and `./scripts/package-source.sh`. Validate the supported hardware, target apps, exclusions, shortcuts, sleep/wake, and permission changes. Verify the oldest supported macOS and build/test Intel separately before claiming support.

For a public binary release, use a stable Developer ID, hardened runtime, notarization, and stapling. Final signing requires the owner's Apple Developer identity. Upload the resulting ZIP as a GitHub Release asset and update the separately maintained website download together. No public binary release is created merely by pushing this repository.
