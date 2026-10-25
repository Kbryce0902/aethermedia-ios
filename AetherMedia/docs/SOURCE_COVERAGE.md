# Source coverage in 0.3.5

Red Light Native is an independent APIBay search adapter. It does not run the original Kodi Red Light add-on, its Python runtime, external scraper modules or configured providers. Seren Native similarly queries YTS/EZTV rather than executing Seren provider packages. These labels must not be interpreted as complete Kodi add-on compatibility.

Cinemeta provides the catalog/search metadata used by the combined Cinemeta & Torrentio provider. Torrentio returns its streams. ProviderManager queries all enabled providers concurrently and includes provider identity in deduplication, so native sources are not intentionally merged into Torrentio. Source sorting favors cloud readiness, resolution, quality and seeds.

The APIBay adapter first searches IMDb plus the episode code for TV, or IMDb alone for movies. If no accepted results remain, it tries title/year/episode. Its matching requires the normalized release title to start with the catalog title. TV requires an exact single-episode marker and either the series edition year or an explicit matching IMDb value, with conflicting years rejected. Season packs and ambiguous multi-episode releases are excluded. Those constraints can exclude valid results, particularly yearless TV releases and aliases; an exact requested title/episode and actual index response are needed to diagnose a specific omission. Do not weaken edition/file identity checks simply to increase counts.

A read-only APIBay request for the public Big Buck Bunny fixture using the current movie-category query returned HTTP200, valid JSON and12 records from the authorized Windows desktop. No account credential was used. This checks one endpoint/query from that network; it does not prove availability on an iPhone or for other lookups.

The cloud importer accepts an individual v1 magnet or SHA1 info-hash and normalizes the latter into a magnet. It adds that torrent to Real-Debrid, not a new provider. In the current stream UI, Copy torrent hash is available under a failed source's Source identity disclosure. It is not a general Copy magnet action on every row. Library > Debrid Cloud > plus > Paste Clipboard > Add to Cloud is the existing manual path. The Red Light Native source chip filters existing results rather than querying another provider ecosystem.

Next work should identify the desired external provider integration, broaden discovery with supported protocols and validated matching, and give each source a direct copy/import action. No such production change or new IPA has been made by this diagnostic review.
