# AetherMedia public-build checkpoint

Version 0.3.5 (8), October 25, 2026. Prepared from the existing app snapshot with a fresh repository history. The unsigned 0.3.5 device IPA has compiled, passed automated tests, and passed device-binary inspection. Live-account and physical-iPhone playback are not yet confirmed.

## Current work

The owner authorized publishing only AetherMedia in a separate public repository. The owner created `Kbryce0902/aethermedia-ios`, default branch `main`. Its public visibility and write access have been verified. App, resources, tests, fixtures, build scripts and reviewed workflows are included. Other projects, old repository history, historical reports, local data and private logs are excluded.

Publication is complete. Source commit `7eaffd7c30fc52ed070b2b35da508440c494aee1` contains87 reviewed app-only files and has only the new repository's initial README commit as its parent. Public source/test blob hashes and paths were verified. No private ancestor commits or other project files were transferred.

The public Mac build passed: https://github.com/Kbryce0902/aethermedia-ios/actions/runs/40234556260, job121293224954, source7eaffd7c30fc52ed070b2b35da508440c494aee1. Actual results:87 core tests,100 active iOS tests plus2 explicit live skips (102 total), zero failures;82 packaging checks; real MKV/AAC and MKV/DTS video-output/time tests; arm64 device archive. Toolchain: Xcode16.4 / Swift6.1.2.

Inspected AetherMedia-0.3.5-unsigned.ipa:20112346 bytes, SHA256049b90c83b4f0c772a7b73453551c15bccfd9260a24db75b39e51a44543a7632. Bundle com.kellen.aethermedia, version0.3.5/build8, iOS17+, devicearm64. Embedded VLCKit device binary and LGPL notices verified. Unsigned/no embedded profile; SideStore signs it. Device IPA artifact12614558069; artifact ZIP SHA2565d0def3670f280d93addd04e5c61bdde9c31f6c7931a7712cd3670d768a11c75. See AetherMedia/verification/RESULTS.json and cloud-device-ipa-0.3.5.json.

The authorized live run is https://github.com/Kbryce0902/aethermedia-ios/actions/runs/40235605030, job121296396243, source8b911b989c07bc9721aab86609e91bab26a45a21 (same Swift sources as the passed ordinary build). The isolated iPhone build and actual app-client device-code request passed. The run then ended after its device-code deadline without receiving authorization. The sanitized report records approval_not_completed_in_time,163 pending device-credential polls, and no token exchange, profile/cloud requests, torrent mutations or playback. Cleanup succeeded. Report artifact12615417606, ZIP SHA2561b0a57a3e33890a1ddfb61d1d06f9e92381c92c83511c8185caa709fbb9b5785; exact report AetherMedia/verification/live-real-debrid-40235605030.json. This attempt establishes no new playback result. The previous display code is expired. Do not start another grant until the owner is ready to approve a fresh normal code.

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


## Source coverage review

The owner reports mostly Cinemeta & Torrentio sources and asks for Red Light magnets. Current0.3.5 Red Light Native is a single APIBay HTTP adapter, not the Kodi Red Light runtime/provider ecosystem. Seren Native is limited to YTS/EZTV. The combined Cinemeta & Torrentio provider gets catalog/search metadata from Cinemeta and source results from Torrentio. ProviderManager queries all enabled source providers concurrently and retains provider IDs during deduplication; it does not intentionally replace native results with Torrentio.

Strict title, year/IMDb and exact-episode checks plus excluded season packs can reduce native coverage. This is a verified implementation limitation; specific lookup failure needs the exact requested title/episode and the phone's provider warning. A public-fixture APIBay query from the authorized Windows desktop returned200 valid JSON with12 records; that does not establish phone connectivity or another title's coverage. No Real-Debrid credential was used. See AetherMedia/docs/SOURCE_COVERAGE.md. No provider code or new build was changed during this review.


## Active 0.3.6 Red Light integration

The owner explicitly wants Red Light access comparable to Kodi Diggz, not manual magnets. Inspected official Red Light 2.9.1 package (SHA2563556c1c7896f2940ee673a89fbf4f38cea8a598e7322dcc46ef55bf06095db1f). Added native HTTP source services: Comet, MediaFusion, Zilean, Torz, Torrentio, PirateBay, Torrent Downloads RSS, AnimeTosho and Nyaa; optional AIOStreams Search API with Keychain configuration. Dedicated Home → Red Light movie/TV browser uses only that source provider. Ordinary discovery retains all providers and reports backend counts/failures. Added unique requested-episode selection from packs; existing cloud selections remain protected. See docs/SOURCE_COVERAGE.md for exact boundaries. This does not implement Kodi Python/Coco/Gears, skins or full add-on menus; do not claim full parity.

Version0.3.6/build9 is prepared for a public standard-Mac build, with isolated regressions and a separate real-network Swift public-source check using Blender's CC film. Initial protocol preflight returned candidates from six services and empty Zilean. No new RD authorization, account mutation or paid service was used. New compilation/test/device archive results are pending. The delivered0.3.5IPA remains the last verified release until0.3.6passes and is inspected. No new live-account authorization run is requested by this commit.
