# Release preparation

The public source repository is https://github.com/AntonMazur/SmoothWheel. SmoothWheel distributes ad-hoc-signed Apple Silicon builds.

## Versioning

- Increment `X` in `X.Y.N` for a major product milestone or breaking change. Reset `Y` and `N` to zero.
- Increment `Y` for a compatible feature update and reset `N` to zero. Saved presets move `0.3.17` to `0.4.0`.
- Increment `N` for fixes and small refinements, such as `0.4.0` to `0.4.1`.

Use `X.Y.N` for the app's `CFBundleShortVersionString`, the changelog and the Homebrew cask. Use `vX.Y.N` for the Git tag. Increment the internal `CFBundleVersion` in `build.sh` independently for each release build.

## Release checks

Run `./scripts/test.sh`, `./build.sh`, and `./scripts/package-source.sh`. Validate the supported hardware, target apps, exclusions, shortcuts, sleep/wake, and permission changes. Verify the oldest supported macOS and build/test Intel separately before claiming support.

Recommended production signing uses a stable Developer ID, hardened runtime, notarization, and stapling. The current release retains the existing ad-hoc distribution and states its limitations explicitly; an Apple Development certificate is not a Developer ID distribution identity. Upload the resulting ZIP as a GitHub Release asset and update the separately maintained website download together. No public binary release is created merely by pushing this repository.

## Homebrew distribution

The [developer-maintained tap](https://github.com/AntonMazur/homebrew-tap) installs the versioned GitHub release ZIP. For every release, update `version` and `sha256` in its `Casks/smoothwheel.rb` after verifying the uploaded asset. Keep existing release assets unchanged so installed casks remain reproducible. Validate the cask metadata and checksum, then check a fresh install and upgrade before updating installation claims.

Keep the architecture, minimum macOS, signing status, and first-launch caveats consistent with the actual artifact. User steps are in [INSTALL.md](INSTALL.md).


## Release evidence

Run `./scripts/measure-engine.sh` as well as the functional/UI checks. Export the public allowlist with `python3 scripts/export-public-metrics.py --version <version>`. Add `--runtime-report <local-report.json>` when a matching physical-wheel session is available. Review `docs/metrics/v<version>.json` before publication. The export includes aggregate timings, coverage and methodology. It excludes raw app routing, PIDs, note contents, recordings, credentials and local paths. Keep the source session immutable while preparing the release. Compare performance only across matched runs.

Publish the verified app ZIP, source ZIP, aggregate metrics JSON and SHA-256 manifest at an immutable version tag. Check the uploaded asset hash, update the Homebrew cask’s version/checksum and the separately maintained website download, and verify both public download paths. Preserve older release assets.
