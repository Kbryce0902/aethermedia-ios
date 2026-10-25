# Red Light source integration — 0.3.6

The previous Red Light Native mode was an APIBay-only adapter. Version 0.3.6 replaces it with independent Swift clients for the HTTP source protocols exposed by Red Light 2.9.1. Home → Red Light opens a dedicated movie/TV browser whose stream search uses Red Light services only. Catalogue/artwork still come from Cinemeta. The ordinary app source sheet also includes these services.

## Implemented services

| Service | Lookup | Configuration |
| --- | --- | --- |
| Comet, MediaFusion, Torrentio | Stremio stream endpoint, IMDb/TMDb plus exact season/episode | HTTPS instance or configured manifest URL |
| Zilean | /dmm/filtered, ImdbId + Season + Episode | HTTPS instance |
| StremThru Torz | /v0/torrents, sid | HTTPS instance |
| PirateBay/APIBay | release-name queries, cat=0 | HTTPS instance; prior APIBay endpoint migrates |
| Torrent Downloads | RSS title search, movie/TV category | HTTPS instance |
| AnimeTosho | JSON title search | HTTPS instance; anime titles only |
| Nyaa | namespaced RSS search | HTTPS instance; anime titles only |
| AIOStreams | /api/v1/search, HTTP Basic Search API credentials | Optional, off until configured; separate instance account |

All native torrent services are enabled by default; anime indexes run only for MediaItems explicitly typed anime. The current Cinemeta movie/TV catalogue normally classifies animation as movie or TV, so those two indexes are not reached by the ordinary catalogue workflow. Absolute-number-only anime mapping is not implemented. AIOStreams needs the same configured instance and Search API account used with Kodi. Its server-side providers are configured on that instance. It supports flattened parsedFile/streamData/info results, HTTPS direct URLs and torrent hashes; P2P-only and header-dependent playback results are excluded, and header exclusions are reported. Instance paths and AIO credentials are saved in Keychain. The iPhone's RD token is never sent to these indexes. Authenticated searches reject cross-origin and insecure redirects.

The source sheet exposes per-service candidate/accepted counts, connection/format failures, and partial failures. One failed service or later name query does not erase other available results. Searches have bounded time/record budgets and propagate cancellation.

ID-scoped lookups accept yearless episode releases while rejecting explicit conflicting years, IMDb IDs and episodes. Unscoped name searches preserve conservative edition-year checks. Season packs can be enabled; resolution chooses the single video with the requested S/E marker, rejects missing/ambiguous matches and contradictory file hints, and preserves existing cloud selections. Whole-show/ranged-episode packs, absolute-number-only anime files and unusual aliases can still be excluded. Torrent Downloads' secondary HTML mirror is not implemented.

## Compatibility boundary

This is a native source-services integration, not the Kodi Python add-on runtime. Kodi ZIP installation, Coco/Gears external scraper modules, Diggz skins, Red Light's account/list/sync menus, Easynews/NZB/local folders and non-RD account integrations are not implemented. The app does not claim full Kodi Red Light parity. Seren remains the separate YTS/EZTV adapter. The combined Cinemeta & Torrentio provider supplies metadata and its own streams; disabling it can remove the ordinary catalogue.

## Primary references and verification

Official upstream README: https://github.com/The-Red-Wiz/TheRedWizard (points to https://repo.redwizard.xyz/).
Official repository descriptor: repository.redwizard-1.2.2.zip → redwizardrepo/main/addons.xml. The repository requires the normal Kodi user agent when serving its package index.
Inspected official plugin.video.redlight-2.9.1.zip: https://repo.redwizard.xyz/redwizardrepo/main/plugin.video.redlight/plugin.video.redlight-2.9.1.zip
SHA256: 3556c1c7896f2940ee673a89fbf4f38cea8a598e7322dcc46ef55bf06095db1f.
Reviewed modules: apis/{comet,mediafusion,torrentio,zilean,torz,piratebay,torrentdownloads,animetosho,nyaa,aiostreams}_api.py; modules/native_torrents.py; scrapers/aiostreams.py and external.py. No upstream Python code, artwork, metadata API keys or account configuration is bundled in AetherMedia. HTTP clients are independently written Swift.

A real public-network preflight with Blender's Creative Commons Big Buck Bunny returned candidates from Comet, MediaFusion, Torz, Torrentio, APIBay and Torrent Downloads; Zilean returned an empty list. This was a desktop/container protocol check, not an iPhone or playback test. The public build separately runs the actual Swift source client against that fixture and uploads a sanitized counts-only report. Isolated tests cover endpoint contracts, matching, partial errors, RSS/JSON decoding, credentials, cancellation and pack selection. Build40242234176/source2be86e7d8c53ac1caae9048dc366d655bcdead9d passed99 active core tests,112 active iOS tests, the device archive and IPA inspection. The separate production Swift real-network check accepted121 source entries: Comet81, MediaFusion25, PirateBay4, Torrentio7, Torz4; Zilean0 and Torrent Downloads invalid RSS on that runner. These are entries before cross-service/provider-manager deduplication; no account was used. See verification/redlight-public-source-40242234176.json. AIOStreams was not tested against an owner's live instance. RD account playback remains unconfirmed after the previous authorization expired.
