# Public snapshot review

Scope: only the AetherMedia source snapshot and two reviewed workflows. The repository will start with new history; it will not be a fork or a mirror of the previous multi-project repository.

The initial 79 app/workflow files were materialized and checked against their Git blob hashes. Original Swift sources, fixtures, assets and third-party notices were preserved. Hosted workflows were adjusted for `main`, limited to this named public repository, and made independent of Apple signing secrets. Public documentation was rewritten without private repository links or historical account-test reports. The package checker now checks the active root workflow instead of an obsolete nested workflow.

Credential review covers known token/private-key patterns, credential assignments, URL credentials, forbidden credential-file names, private project names and local storage references. Matches in DTO coding keys and Keychain identifiers are field names. The Real-Debrid default client ID is a public OAuth application identifier. Test credentials are synthetic local fixtures. Access/refresh tokens and device client secrets are obtained at runtime rather than included in the snapshot. Binary assets are an app icon and generated playback fixtures.

No account credential was found in the reviewed snapshot. This is a snapshot review, not a guarantee that future edits cannot add sensitive data. Run `python3 AetherMedia/scripts/check_public_snapshot.py` before publishing updates. Ignore rules exclude credentials, build products and private live-test files. Raw private live-test logs are never uploaded.

The review does not establish a successful 0.3.5 compile or playback test. Those remain pending until actual hosted results are inspected.
