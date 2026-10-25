# AetherMedia public-build checkpoint

Version 0.3.5 (8), October 25, 2026. Prepared from the existing app snapshot with a fresh repository history. No compiled 0.3.5 IPA or successful live playback is yet confirmed.

## Current work

The owner authorized publishing only AetherMedia in a separate public repository. The owner created `Kbryce0902/aethermedia-ios`, default branch `main`. Its public visibility and write access have been verified. App, resources, tests, fixtures, build scripts and reviewed workflows are included. Other projects, old repository history, historical reports, local data and private logs are excluded.

Repository creation is complete. Uploading the reviewed app-only snapshot is the current step. Only the new repository's initial README commit will be used as a parent; no commits from the previous repository are transferred. Compilation and live testing remain pending actual workflow results.

## 0.3.5 behavior and validation

The real account test observed public addMagnet201 followed by first-info404/code7. Delayed visibility is a hypothesis to test, not a proven server cause. `getNewTorrentInfo` now retries the same newly created ID at most six times (also capped by preparation attempts), only for exact HTTP404/service7. It preserves cancellation and account checks, never submits a second magnet, and keeps hash/file validation and existing cloud selections intact. Persistent404 and other refusals retain typed errors.

Five new regression cases cover startup recovery, bounded persistent404, ordinary stale detail behavior, other refusals and malformed identity. Expected test totals are 87 core, 100 active iOS, and 2 opt-in live skips; actual results must replace these expectations after CI runs. Source inventory is 43 app Swift files and 15 test Swift files.

The earlier compiled app's empty204 cloud-list repair and actual MKV/AAC and MKV/DTS decoding tests passed. Live OAuth, Premium profile, empty204 cloud handling and public torrent creation were verified, but network playback was not reached. An independent HTTP451/code35 source refusal is not solved by retries.

## Build and live-test sequence

1. Publish this reviewed snapshot with fresh history, confirm public visibility and no unrelated files or ancestors.
2. Run the ordinary build on the standard `macos-15` runner. The workflow refuses private-repository or differently named repository runs. Inspect tests, device archive, IPA bundle/version/arm64 platform, embedded VLCKit and notices.
3. Only after the build passes, explicitly request the opt-in live run by changing `AetherMedia/verification/LIVE_TEST_REQUEST.json` or using the manual workflow. Obtain a fresh normal display code and await owner authorization. Prior codes cannot be reused.
4. Use the real HTTP client; preserve existing cloud files/selections. Only delete the public test entry created by this run and disable its temporary access token. Keep raw logs, grants and signed URLs out of public output.
5. Record actual results here, and deliver the inspected device IPA for SideStore.

No billing/payment/spending setting is changed by this repository. If an account restriction still blocks public jobs, report the actual annotation and stop retrying. Do not add paid runners or increase a budget.
