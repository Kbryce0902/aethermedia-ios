# Install on iPhone

Requires iOS 17 or later and a compiled arm64 device IPA. This repository's source files are not installable by themselves.

1. Open a successful **Build AetherMedia iPhone IPA** run and download **AetherMedia-iPhone**.
2. Extract the archive and import the `.ipa` into SideStore.
3. Sign with your own account. Use the same signing account and bundle identifier when updating an existing app, and install over it to preserve its data.
4. Open Settings in AetherMedia and authorize Real-Debrid through its normal device-code page.

The hosted build does not require an Apple developer subscription or a signing certificate. SideStore performs signing and determines its own account/device requirements. Compiling and signing are separate steps.

Version0.3.5 (8) compiled and passed automated tests and device IPA inspection; real-account and physical-iPhone playback acceptance are pending. Do not label a source ZIP or simulator bundle as an iPhone IPA. App Store distribution and TestFlight are outside this build workflow.
