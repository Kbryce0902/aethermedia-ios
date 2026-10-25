#!/usr/bin/env python3
"""Package a compiled iOS device app for a sideloading tool to re-sign."""
import argparse, plistlib, struct, zipfile, subprocess
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('app',type=Path)
parser.add_argument('--output',type=Path,default=Path('build/AetherMedia-unsigned.ipa'))
parser.add_argument('--signed',action='store_true',help='Verify and package an Apple-signed device app.')
args=parser.parse_args()
app=args.app.resolve()
if not app.is_dir() or app.suffix!='.app': parser.error('Input must be a compiled .app directory, not a source folder.')
try: info=plistlib.loads((app/'Info.plist').read_bytes())
except Exception as error: parser.error('Compiled app Info.plist is missing or invalid: '+str(error))
if info.get('CFBundlePackageType')!='APPL': parser.error('Bundle is not an iOS application.')
if 'iPhoneOS' not in info.get('CFBundleSupportedPlatforms',[]): parser.error('A device build is required; simulator apps cannot be installed on an iPhone.')
name=info.get('CFBundleExecutable','')
if not name or Path(name).name!=name: parser.error('Invalid app executable name.')
executable=app/name
if not executable.is_file(): parser.error('The compiled app executable is missing.')
header=executable.read_bytes()[:32]
# This project's generic iOS archive must produce a thin arm64 Mach-O, never a Linux/Windows binary.
if len(header)<32 or header[:4]!=b'\xcf\xfa\xed\xfe' or struct.unpack_from('<I',header,4)[0]!=0x0100000C:
    parser.error('Expected an arm64 Mach-O executable from a generic iOS archive.')
if args.signed:
    if not (app/'embedded.mobileprovision').is_file(): parser.error('Signed sideload packages require an embedded provisioning profile.')
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
args.output.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(args.output,'w',zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob('*')):
        if path.is_symlink(): parser.error('Unexpected symbolic link in app bundle; use Xcode export instead.')
        if path.is_file(): archive.write(path,'Payload/'+app.name+'/'+path.relative_to(app).as_posix())
print(str(args.output.resolve()))
print('Signed device IPA created; installation requires a device covered by its provisioning profile.' if args.signed else 'Unsigned device IPA created. It must be re-signed by SideStore/AltStore before installation.')
