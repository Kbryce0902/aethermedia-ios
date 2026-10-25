# AetherMedia public-build checkpoint

Version 0.3.5 (8), October 25, 2026. Prepared from the existing app snapshot with a fresh repository history. The unsigned 0.3.5 device IPA has compiled, passed automated tests, and passed device-binary inspection. Live-account and physical-iPhone playback are not yet confirmed.

## Current work

The owner authorized publishing only AetherMedia in a separate public repository. The owner created `Kbryce0902/aethermedia-ios`, default branch `main`. Its public visibility and write access have been verified. App, resources, tests, fixtures, build scripts and reviewed workflows are included. Other projects, old repository history, historical reports, local data and private logs are excluded.

Publication is complete. Source commit `7eaffd7c30fc52ed070b2b35da508440c494aee1` contains87 reviewed app-only files and has only the new repository's initial README commit as its parent. Public source/test blob hashes and paths were verified. No private ancestor commits or other project files were transferred.

The public Mac build passed: https://github.com/Kbryce0902/aethermedia-ios/actions/runs/40234556260, job121293224954, source7eaffd7c30fc52ed070b2b35da508440c494aee1. Actual results:87 core tests,100 active iOS tests plus2 explicit live skips (102 total), zero failures;82 packaging checks; real MKV/AAC and MKV/DTS video-output/time tests; arm64 device archive. Toolchain: Xcode16.4 / Swift6.1.2.

Inspected AetherMedia-0.3.5-unsigned.ipa:20112346 bytes, SHA256049b90c83b4f0c772a7b73453551c15bccfd9260a24db75b39e51a44543a7632. Bundle com.kellen.aethermedia, version0.3.5/build8, iOS17+, devicearm64. Embedded VLCKit device binary and LGPL notices verified. Unsigned/no embedded profile; SideStore signs it. Device IPA artifact12614558069; artifact ZIP SHA2565d0def3670f280d93addd04e5c61bdde9c31f6c7931a7712cd3670d768a11c75. See AetherMedia/verification/RESULTS.json and cloud-device-ipa-0.3.5.json.

The authorized live run is https://github.com/Kbryce0902/aethermedia-ios/actions/runs/40235605030, job121296396243, source8b911b989c07bc9721aab86609e91bab26a45a21 (same Swift sources as the passed ordinary build). The public-only guard and credential check passed; its isolated virtual iPhone is building. No fresh code has been observed yet. Obtain its sign-in artifact when uploaded, provide only that fresh normal code promptly, and await owner approval. Do not reuse previous codes or claim real playback passed before the sanitized report confirms it.

## 0.3.5 behavior and validation

The real account test observed public addMagnet201 followed by first-info404/code7. Delayed visibility is a hypothesis to test, not a proven server cause. `getNewTorrentInfo` now retries the same newly created ID at most six times (also capped by preparation attempts), only for exact HTTP404/service7. It preserves cancellation and account checks, never submits a second magnet, and keeps hash/file validation and existing cloud selections intact. Persistent404 and other refusals retain typed errors.

Five new regression cases cover startup recovery, bounded persistent404, ordinary stale detail behavior, other refusals and malformed identity. Actual passed test totals are87 core and100 active iOS, with2 opt-in live skips. Source inventory is 43 app Swift files and 15 test Swift files.

The earlier compiled app's empty204 cloud-list repair and actual MKV/AAC and MKV/DTS decoding tests passed. Live OAuth, Premium profile, empty204 cloud handling and public torrent creation were verified, but network playback was not reached. An independent HTTP451/code35 source refusal is not solved by retries.

## Build and live-test sequence

1. Publish this reviewed snapshot with fresh history, confirm public visibility and no unrelated files or ancestors.
2. Run the ordinary build on the standard `macos-15` runner. The workflow refuses private-repository or differently named repository runs. Inspect tests, device archive, IPA bundle/version/arm64 platform, embedded VLCKit and notices.
3. Only after the build passes, explicitly request the opt-in live run by changing `AetherMedia/verification/LIVE_TEST_REQUEST.json` or using the manual workflow. Obtain a fresh normal display code and await owner authorization. Prior codes cannot be reused.
4. Use the real HTTP client; preserve existing cloud files/selections. Only delete the public test entry created by this run and disable its temporary access token. Keep raw logs, grants and signed URLs out of public output.
5. Record actual results here, and deliver the inspected device IPA for SideStore.

No billing/payment/spending setting is changed by this repository. If an account restriction still blocks public jobs, report the actual annotation and stop retrying. Do not add paid runners or increase a budget.
