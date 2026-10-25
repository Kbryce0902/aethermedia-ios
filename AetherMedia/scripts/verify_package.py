#!/usr/bin/env python3
"""Offline packaging checks; this does not replace an iOS build or XCTest run."""
from pathlib import Path
import hashlib, json, plistlib, re, subprocess, sys, tempfile, xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
checks=0
def check(condition,message):
    global checks
    if not condition: raise AssertionError(message)
    checks+=1
    print('PASS:',message)

project=(ROOT/'AetherMedia.xcodeproj/project.pbxproj').read_text()
scheme=ET.parse(ROOT/'AetherMedia.xcodeproj/xcshareddata/xcschemes/AetherMedia.xcscheme').getroot()
check('com.apple.product-type.application' in project,'Xcode iOS app target exists')
check('com.apple.product-type.bundle.unit-test' in project,'Xcode unit-test target exists')
check(bool(scheme.find('TestAction/Testables/TestableReference') is not None),'shared scheme includes tests')
objects=set(re.findall(r'^([A-F0-9]{24}) =',project,re.M))
refs=set(re.findall(r'(?<![A-F0-9])[A-F0-9]{24}(?![A-F0-9])',project))
check(refs<=objects,'all project object references resolve')
for folder in ['Sources','Tests']:
    files=list((ROOT/folder).rglob('*.swift'))
    check(bool(files),folder+' contains Swift files')
    for path in files:
        rel=path.relative_to(ROOT).as_posix()
        check(json.dumps(rel) in project,rel+' is included in the Xcode project')
info=plistlib.loads((ROOT/'Resources/Info.plist').read_bytes())
check(info.get('CFBundlePackageType')=='APPL','application Info.plist is valid')
check('audio' in info.get('UIBackgroundModes',[]),'background playback capability is configured')
check('NSAppTransportSecurity' not in info,'no blanket insecure transport exception')
for path in (ROOT/'Resources/Assets.xcassets').rglob('Contents.json'):
    content=json.loads(path.read_text())
    for entry in content.get('images',[]):
        if 'filename' in entry: check((path.parent/entry['filename']).is_file(),'referenced app icon exists')
production='\n'.join(p.read_text() for p in (ROOT/'Sources').rglob('*.swift'))
check('MOCK_TORRENT' not in production and 'MockRealDebridClient' not in production,'mock client is excluded from production sources')
check('tt0000000' not in production and 'dyn_' not in production,'no fabricated search results')
check('instantAvailability/' not in production,'disabled cache endpoint is not requested')
check('"grant_type": "refresh_token"' not in production,'legacy incorrect refresh grant was removed')
for path in (ROOT/'Sources/AetherMedia/Services/Providers').glob('*.swift'):
    check(not re.search(r'urn:btih:[A-Fa-f0-9]{20,}',path.read_text()),path.name+' has no fixed torrent hashes')
for path in [ROOT/'scripts/build_ipa.sh',ROOT/'scripts/test_ios.sh']:
    subprocess.run(['bash','-n',str(path)],check=True)
check(True,'build/test shell scripts have valid Bash syntax')
# A source tree and a simulator bundle must never be mislabeled as a device IPA.
with tempfile.TemporaryDirectory() as directory:
    app=Path(directory)/'Fixture.app';app.mkdir()
    (app/'Info.plist').write_bytes(plistlib.dumps({'CFBundlePackageType':'APPL','CFBundleSupportedPlatforms':['iPhoneSimulator'],'CFBundleExecutable':'Fixture'}))
    result=subprocess.run([sys.executable,str(ROOT/'scripts/package_ipa.py'),str(app),'--output',str(Path(directory)/'invalid.ipa')],capture_output=True,text=True)
    check(result.returncode!=0 and 'simulator' in result.stderr,'IPA packager rejects simulator bundles')
    result=subprocess.run([sys.executable,str(ROOT/'scripts/package_ipa.py'),str(ROOT)],capture_output=True,text=True)
    check(result.returncode!=0,'IPA packager rejects uncompiled source folders')
check((ROOT.parent/'.github/workflows/aethermedia-ios.yml').is_file(),'hosted macOS build workflow is included')
print(f'{checks} offline checks passed. No iOS compilation, signing or device test is implied.')
