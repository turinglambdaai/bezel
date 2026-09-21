# Bezel Release Gate

A Bezel release is publishable only when every item below is satisfied.

## Repository integrity

- [ ] `racket scripts/check-version.rkt vX.Y.Z` succeeds.
- [ ] Generated bindings are reproducible (`git diff --exit-code` after regeneration).
- [ ] Unit/integration tests pass on Linux, Windows, and macOS.
- [ ] Documentation builds without errors.

## Native runtime artifacts

For every supported release platform:

- [ ] `libbezel`/`bezel.dll` is present and reports the expected ABI.
- [ ] Qt Core, Gui, and Widgets runtime libraries are bundled.
- [ ] A usable Qt platform plugin is bundled.
- [ ] The runtime is relocatable and does not depend on the CI build directory.
- [ ] `raco bezel doctor` succeeds after installing only the packaged Bezel archive.
- [ ] `scripts/native-smoke.rkt` creates a real QApplication and widget using the packaged runtime.

## Release assets

- [ ] Native runtime archive exists for every supported platform.
- [ ] Self-contained `bezel-lib-<platform>.zip` exists for every supported platform.
- [ ] SHA-256 checksums are published with the GitHub Release.
- [ ] Release tag matches all package/shim/changelog versions.
- [ ] Release notes describe compatibility and breaking changes.

## Commercial distribution

- [ ] Qt redistribution obligations for the chosen Qt license have been reviewed for the product being shipped.
- [ ] Windows production applications are code-signed when distributed to end users.
- [ ] macOS production applications are code-signed and notarized when distributed outside development environments.
- [ ] A clean-machine installation test has been performed for each supported OS/architecture.

The GitHub Actions workflows automate the technical gates. Signing credentials and product-specific licensing review remain deployment responsibilities of the application vendor.
