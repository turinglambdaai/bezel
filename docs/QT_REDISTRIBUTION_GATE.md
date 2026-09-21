# Qt redistribution gate

Bezel's CI can build portable runtime bundles that contain Qt shared libraries and plugins. A technically valid bundle is not automatically a legally distributable bundle.

Tagged GitHub Releases therefore require an explicit repository-owner acknowledgement before any Qt runtime is published.

## Repository variables

Configure these GitHub Actions repository variables before creating a production tag:

- `BEZEL_QT_REDISTRIBUTION_ACK=approved`
- `BEZEL_QT_LICENSE_MODE=commercial` or `BEZEL_QT_LICENSE_MODE=lgpl`
- for `lgpl`, `BEZEL_QT_SOURCE_OFFER_URL` must identify the distributor-controlled corresponding-source/source-offer location for the exact Qt build being redistributed

The Release workflow fails closed when these values are absent or invalid. Manual workflow-dispatch runs can still build and smoke-test artifacts, but they do not publish a GitHub Release.

## Why the gate exists

Bezel is MIT licensed, but the Qt binaries bundled by the native packagers keep their own licenses. The repository owner is responsible for ensuring that the exact Qt build used for a release is covered by the selected redistribution terms.

For LGPL distribution, Qt's published guidance includes obligations such as providing the LGPL terms and a prominent notice, allowing relinking/replacement of the LGPL libraries, and making corresponding Qt source available (or providing an appropriate written offer) under the distributor's control. Product-specific legal review remains appropriate.

For commercial Qt licensing, the acknowledgement means the repository owner has confirmed that the Qt build and intended redistribution are covered by the applicable commercial agreement. The public workflow cannot verify private license entitlements.

## Release record

A successful tagged release includes `QT-REDISTRIBUTION.txt`. It records the declared redistribution mode and, for LGPL releases, the configured source/source-offer location. This is an audit aid, not a substitute for the actual license obligations.
