#!/bin/bash
# Optional GitHub-hosted signing. Credentials exist only in repository secrets and runner temp.
set -euo pipefail
set +x
cd "$(dirname "$0")/.."
: "${AETHER_CERTIFICATE_P12_BASE64:?Configure the certificate repository secret.}"
: "${AETHER_PROVISION_PROFILE_BASE64:?Configure the provisioning-profile repository secret.}"
sign_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/aether-sign.XXXXXX")
export AETHER_SIGN_DIR="$sign_dir"
keychain_path="$sign_dir/signing.keychain-db"
keychain_password=$(openssl rand -hex 32)
cleanup() {
  security delete-keychain "$keychain_path" >/dev/null 2>&1 || true
  rm -rf "$sign_dir"
}
trap cleanup EXIT
python3 - <<'PY'
import base64,os
from pathlib import Path
root=Path(os.environ['AETHER_SIGN_DIR'])
for key,name in [('AETHER_CERTIFICATE_P12_BASE64','certificate.p12'),('AETHER_PROVISION_PROFILE_BASE64','profile.mobileprovision')]:
    path=root/name
    path.write_bytes(base64.b64decode(os.environ[key],validate=True))
    path.chmod(0o600)
PY
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 3600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$sign_dir/certificate.p12" -P "${AETHER_CERTIFICATE_PASSWORD:-}" -A -t cert -f pkcs12 -k "$keychain_path" >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain_path" >/dev/null
security find-identity -v -p codesigning "$keychain_path" > "$sign_dir/identities.txt"
security cms -D -i "$sign_dir/profile.mobileprovision" > "$sign_dir/profile.plist"
app_path='build/AetherMedia.xcarchive/Products/Applications/AetherMedia.app'
export AETHER_SIGN_APP="$app_path"
identity=$(python3 - <<'PY'
import datetime,fnmatch,hashlib,os,plistlib,re
from pathlib import Path
root=Path(os.environ['AETHER_SIGN_DIR']);app=Path(os.environ['AETHER_SIGN_APP'])
profile=plistlib.loads((root/'profile.plist').read_bytes());info=plistlib.loads((app/'Info.plist').read_bytes())
if profile['ExpirationDate'].replace(tzinfo=datetime.timezone.utc)<=datetime.datetime.now(datetime.timezone.utc):raise SystemExit('The provisioning profile is expired.')
if not profile.get('ProvisionedDevices') and not profile.get('ProvisionsAllDevices'):raise SystemExit('Use a development/ad-hoc device profile; an App Store profile cannot install this IPA directly.')
allowed={hashlib.sha1(cert).hexdigest().upper() for cert in profile.get('DeveloperCertificates',[])}
identities=re.findall(r'\b[0-9A-F]{40}\b',(root/'identities.txt').read_text())
identity=next((i for i in identities if i in allowed),None)
if identity is None:raise SystemExit('The signing certificate does not match the provisioning profile.')
entitlements=dict(profile['Entitlements']);bundle=info['CFBundleIdentifier']
pattern=entitlements['application-identifier'];prefix=pattern.split('.',1)[0]
appid=prefix+'.'+bundle
if not fnmatch.fnmatchcase(appid,pattern):raise SystemExit('The provisioning profile does not cover this app bundle ID: '+bundle)
entitlements['application-identifier']=appid
if 'keychain-access-groups' in entitlements:
    entitlements['keychain-access-groups']=[group.replace('*',bundle) for group in entitlements['keychain-access-groups']]
(root/'entitlements.plist').write_bytes(plistlib.dumps(entitlements))
if any(app.rglob('*.appex')):raise SystemExit('Per-extension provisioning must be configured before signing extensions.')
print(identity)
PY
)
cp "$sign_dir/profile.mobileprovision" "$app_path/embedded.mobileprovision"
if [[ -d "$app_path/Frameworks" ]]; then
  while IFS= read -r -d '' binary; do
    codesign --force --sign "$identity" --keychain "$keychain_path" --timestamp=none "$binary"
  done < <(find "$app_path/Frameworks" -type f -name '*.dylib' -print0)
  while IFS= read -r -d '' framework; do
    codesign --force --sign "$identity" --keychain "$keychain_path" --timestamp=none "$framework"
  done < <(find "$app_path/Frameworks" -depth -type d -name '*.framework' -print0)
fi
codesign --force --sign "$identity" --keychain "$keychain_path" --timestamp=none --entitlements "$sign_dir/entitlements.plist" "$app_path"
codesign --verify --deep --strict "$app_path"
python3 scripts/package_ipa.py "$app_path" --output build/AetherMedia-signed.ipa --signed
