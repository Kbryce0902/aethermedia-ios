# AetherMedia

Native SwiftUI app for iOS 17+, bundle `com.kellen.aethermedia`, version 0.3.5 (8).

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

Cinemeta supplies metadata. Torrentio-style source discovery, limited independent native Seren-style YTS/EZTV providers, Red Light-style APIBay discovery, existing Debrid cloud files, and manual magnets are supported. The original Kodi Python add-ons and arbitrary provider packs do not run in this app.

Real-Debrid resolution preserves existing cloud file selections and validates source identity and file/link mappings. Compatible streams use AVPlayer; the bundled VideoLAN player handles extended formats. Extended-player PiP and AirPlay are not implemented.

## Current verification

The previous compiled version passed core/iOS tests, device archiving, and actual MKV AAC/DTS decoding tests. A real authorized run verified OAuth, Premium profile decoding, the HTTP 204 cloud-list repair, and public torrent creation. It stopped at HTTP 404/code 7 on the first new-torrent detail read before video playback. The new bounded retry has regression coverage prepared, but 0.3.5 has not yet compiled or passed these tests.

HTTP 451/code 35 is an explicit refusal for a selected source; startup retries do not override it. Successful physical-iPhone or live-account playback of 0.3.5 is not yet confirmed.

See the root [HANDOFF.md](../HANDOFF.md) for the next actions.
