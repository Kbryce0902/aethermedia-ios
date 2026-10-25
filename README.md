# AetherMedia for iPhone

A standalone iOS 17+ media app with a touch interface, Real-Debrid device authorization, metadata/source providers, and bundled extended video playback.

This repository contains only AetherMedia. It starts with a fresh source snapshot and does not include other projects, previous repository history, account data, or old workflow logs.

Version 0.3.6 (build 9) adds a dedicated Red Light browser and native clients for its source services, optional AIOStreams configuration, backend diagnostics and exact episode selection from season packs. See [source coverage](AetherMedia/docs/SOURCE_COVERAGE.md) for supported services and the Kodi runtime boundary. New compilation and test results are pending. The prior 0.3.5 device build and automated tests passed; real-account and physical-iPhone playback remain unconfirmed.

See [app instructions](AetherMedia/README.md), [installation](AetherMedia/INSTALL_IPHONE.md), [current handoff](HANDOFF.md), and [publication review](PUBLICATION_REVIEW.md).

The build workflow uses a standard `macos-15` runner and runs only while this repository is public. It produces an unsigned device IPA for SideStore to sign. No Apple signing credentials are required by the hosted workflow. GitHub documents standard public-repository runner compute as free; account restrictions and service availability can still prevent jobs from starting.

The opt-in live test needs normal owner device authorization each time. Its raw logs, private pending grant, access/refresh tokens, signed playback URLs, and account response values are not published. Only a short-lived authorization display card and a sanitized result are uploaded.

Third-party components retain their own licenses. See [ThirdPartyNotices.txt](AetherMedia/Resources/ThirdPartyNotices.txt).
