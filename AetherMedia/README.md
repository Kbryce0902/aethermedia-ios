# AetherMedia

Native SwiftUI app for iOS 17+, bundle `com.kellen.aethermedia`, version 0.3.6 (9).

## Build and install

The root GitHub Actions workflow compiles the app, runs portable and iOS simulator tests, archives an arm64 device app, and uploads `AetherMedia-iPhone`. Download its IPA and install through SideStore using the same signing account as an existing installation.

On a Mac with full Xcode:

```bash
cd AetherMedia
python3 scripts/check_public_snapshot.py
python3 scripts/verify_package.py
swift test --disable-swift-testing
bash scripts/test_ios.sh
bash scripts/build_ipa.sh
```

The output is `build/AetherMedia-unsigned.ipa`. Local packaging checks alone do not establish a successful device build.

## Providers and playback

Cinemeta supplies metadata. Torrentio-style source discovery, limited independent native Seren-style YTS/EZTV providers, Red Light native source services and optional AIOStreams, existing Debrid cloud files, and manual magnets are supported. The original Kodi Python add-ons and arbitrary provider packs do not run in this app.

Real-Debrid resolution preserves existing cloud file selections and validates source identity and file/link mappings. Compatible streams use AVPlayer; the bundled VideoLAN player handles extended formats. Extended-player PiP and AirPlay are not implemented.

## Current verification

Version0.3.5 passed87 core tests and100 active iOS tests, plus2 explicitly skipped live methods, with zero failures. Real MKV/AAC and MKV/DTS output/time tests and arm64 device archiving passed. The inspected unsigned IPA contains its device decoder and notices. Build: https://github.com/Kbryce0902/aethermedia-ios/actions/runs/40234556260.

Earlier real authorized runs verified OAuth, Premium profile decoding, the empty204 cloud-list repair and public torrent creation, then stopped before playback at first-info404/code7. The0.3.5 bounded retry passed regression tests; the fresh real-account test is pending owner authorization and actual results.

HTTP 451/code 35 is an explicit refusal for a selected source; startup retries do not override it. Successful physical-iPhone or live-account playback of 0.3.5 is not yet confirmed.

See the root [HANDOFF.md](../HANDOFF.md) for the next actions.


0.3.6 adds Home → Red Light with a separate movie/TV browser, Settings → Red Light Settings for service toggles/instances/AIOStreams, per-service candidate/accepted counts and season-pack episode selection. See docs/SOURCE_COVERAGE.md. Full Kodi Python/Coco/Gears execution is not implemented. New build verification is pending.
