#!/usr/bin/env python3
"""Generate the checked-in Xcode app/test project, without XcodeGen or dependencies."""
from pathlib import Path
import hashlib, json, plistlib, xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def quote(s): return json.dumps(str(s))
def serialize(value):
    if isinstance(value, dict): return '{ ' + ' '.join(f'{quote(k)} = {serialize(v)};' for k,v in value.items()) + ' }'
    if isinstance(value, list): return '(' + ', '.join(serialize(v) for v in value) + ')'
    if isinstance(value, Ref): return value.value
    return quote(value)
class Ref:
    def __init__(self, key): self.value = ident(key)
def ref(key): return Ref(key)
objects={}
def add(key, isa, **values): objects[ident(key)]={'isa':isa, **values}; return ref(key)
appfiles = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT/'Sources').rglob('*.swift'))
testfiles = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT/'Tests').rglob('*.swift'))
for path in appfiles+testfiles:
    add('file:'+path,'PBXFileReference',lastKnownFileType='sourcecode.swift',name=Path(path).name,path=path,sourceTree='SOURCE_ROOT')
    add('build:'+path,'PBXBuildFile',fileRef=ref('file:'+path))
add('assets','PBXFileReference',lastKnownFileType='folder.assetcatalog',path='Resources/Assets.xcassets',sourceTree='SOURCE_ROOT')
add('info','PBXFileReference',lastKnownFileType='text.plist.xml',path='Resources/Info.plist',sourceTree='SOURCE_ROOT')
add('assetbuild','PBXBuildFile',fileRef=ref('assets'))
add('vlcpackage','XCRemoteSwiftPackageReference',repositoryURL='https://github.com/videolan/vlckit.git',requirement={'kind':'revision','revision':'2e0868f5ed40fe59cd92f377645fdcc260c6e759'})
for name in ['app','test']:
    add(name+'vlc','XCSwiftPackageProductDependency',package=ref('vlcpackage'),productName='VLCKit')
    add(name+'vlcbuild','PBXBuildFile',productRef=ref(name+'vlc'))
extra_resources=['Resources/ThirdPartyNotices.txt']
fixture_files=sorted(p.relative_to(ROOT).as_posix() for p in (ROOT/'Tests/AetherMediaTests/Fixtures').glob('*') if p.is_file())
for path in extra_resources+fixture_files:
    add('file:'+path,'PBXFileReference',lastKnownFileType='text' if path.endswith('.txt') else 'file',path=path,sourceTree='SOURCE_ROOT')
    add('build:'+path,'PBXBuildFile',fileRef=ref('file:'+path))
add('appproduct','PBXFileReference',explicitFileType='wrapper.application',includeInIndex='0',path='AetherMedia.app',sourceTree='BUILT_PRODUCTS_DIR')
add('testproduct','PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex='0',path='AetherMediaTests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
add('appgroup','PBXGroup',children=[ref('file:'+p) for p in appfiles],name='Sources',sourceTree='<group>')
add('testgroup','PBXGroup',children=[ref('file:'+p) for p in testfiles],name='Tests',sourceTree='<group>')
add('resourcegroup','PBXGroup',children=[ref('assets'),ref('info')]+[ref('file:'+p) for p in extra_resources],name='Resources',sourceTree='<group>')
add('products','PBXGroup',children=[ref('appproduct'),ref('testproduct')],name='Products',sourceTree='<group>')
add('rootgroup','PBXGroup',children=[ref('appgroup'),ref('testgroup'),ref('resourcegroup'),ref('products')],sourceTree='<group>')
for key, files in [('appsources',appfiles),('testsources',testfiles)]:
    add(key,'PBXSourcesBuildPhase',buildActionMask='2147483647',files=[ref('build:'+p) for p in files],runOnlyForDeploymentPostprocessing='0')
for key in ['appframeworks','testframeworks']:
    add(key,'PBXFrameworksBuildPhase',buildActionMask='2147483647',files=[ref(('app' if key=='appframeworks' else 'test')+'vlcbuild')],runOnlyForDeploymentPostprocessing='0')
add('appresources','PBXResourcesBuildPhase',buildActionMask='2147483647',files=[ref('assetbuild')]+[ref('build:'+p) for p in extra_resources],runOnlyForDeploymentPostprocessing='0')
add('testresources','PBXResourcesBuildPhase',buildActionMask='2147483647',files=[ref('build:'+p) for p in fixture_files],runOnlyForDeploymentPostprocessing='0')
add('proxy','PBXContainerItemProxy',containerPortal=ref('project'),proxyType='1',remoteGlobalIDString=ref('app'),remoteInfo='AetherMedia')
add('dependency','PBXTargetDependency',target=ref('app'),targetProxy=ref('proxy'))
for configuration in ['Debug','Release']:
    settings={
        'CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','ALWAYS_SEARCH_USER_PATHS':'NO',
        'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0',
        'SWIFT_STRICT_CONCURRENCY':'targeted','ENABLE_USER_SCRIPT_SANDBOXING':'YES',
        'DEBUG_INFORMATION_FORMAT':'dwarf' if configuration=='Debug' else 'dwarf-with-dsym',
        'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if configuration=='Debug' else '-O',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG $(inherited)' if configuration=='Debug' else '$(inherited)',
        'ENABLE_TESTABILITY':'YES' if configuration=='Debug' else 'NO',
        'GCC_C_LANGUAGE_STANDARD':'gnu17','CLANG_CXX_LANGUAGE_STANDARD':'gnu++20',
    }
    add('project'+configuration,'XCBuildConfiguration',buildSettings=settings,name=configuration)
    common={'PRODUCT_NAME':'$(TARGET_NAME)','TARGETED_DEVICE_FAMILY':'1',
            'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO',
            'ENABLE_DEBUG_DYLIB':'NO','CODE_SIGN_STYLE':'Automatic','DEVELOPMENT_TEAM':'','CURRENT_PROJECT_VERSION':'9','MARKETING_VERSION':'0.3.6',
            'LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks']}
    add('app'+configuration,'XCBuildConfiguration',buildSettings={**common,
        'PRODUCT_BUNDLE_IDENTIFIER':'com.kellen.aethermedia','GENERATE_INFOPLIST_FILE':'NO',
        'INFOPLIST_FILE':'Resources/Info.plist','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon',
        'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor'},name=configuration)
    add('test'+configuration,'XCBuildConfiguration',buildSettings={**common,
        'PRODUCT_BUNDLE_IDENTIFIER':'com.kellen.aethermedia.tests','GENERATE_INFOPLIST_FILE':'YES',
        'TEST_HOST':'$(BUILT_PRODUCTS_DIR)/AetherMedia.app/AetherMedia','BUNDLE_LOADER':'$(TEST_HOST)'},name=configuration)
for key in ['project','app','test']:
    add(key+'configs','XCConfigurationList',buildConfigurations=[ref(key+'Debug'),ref(key+'Release')],defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
add('app','PBXNativeTarget',buildConfigurationList=ref('appconfigs'),buildPhases=[ref('appsources'),ref('appframeworks'),ref('appresources')],
    packageProductDependencies=[ref('appvlc')],buildRules=[],dependencies=[],name='AetherMedia',productName='AetherMedia',productReference=ref('appproduct'),productType='com.apple.product-type.application')
add('test','PBXNativeTarget',buildConfigurationList=ref('testconfigs'),buildPhases=[ref('testsources'),ref('testframeworks'),ref('testresources')],
    packageProductDependencies=[ref('testvlc')],buildRules=[],dependencies=[ref('dependency')],name='AetherMediaTests',productName='AetherMediaTests',productReference=ref('testproduct'),productType='com.apple.product-type.bundle.unit-test')
add('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'1600',
    'TargetAttributes':{ident('app'):{'CreatedOnToolsVersion':'16.0','SystemCapabilities':{'com.apple.BackgroundModes':{'enabled':'1'}}},
                        ident('test'):{'CreatedOnToolsVersion':'16.0','TestTargetID':ref('app')}}},
    buildConfigurationList=ref('projectconfigs'),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings='0',knownRegions=['en','Base'],
    packageReferences=[ref('vlcpackage')],mainGroup=ref('rootgroup'),productRefGroup=ref('products'),projectDirPath='',projectRoot='',targets=[ref('app'),ref('test')])
project=ROOT/'AetherMedia.xcodeproj'; project.mkdir(exist_ok=True)
lines=['// !$*UTF8*$!','{','archiveVersion = 1;','classes = {};','objectVersion = 56;','objects = {']
for key,value in objects.items(): lines.append(f'{key} = {serialize(value)};')
lines += ['};',f'rootObject = {ident("project")};','}']
(project/'project.pbxproj').write_text('\n'.join(lines)+'\n')

def buildable(parent,key,name):
    ET.SubElement(parent,'BuildableReference',{'BuildableIdentifier':'primary','BlueprintIdentifier':ident(key),'BuildableName':name,'BlueprintName':'AetherMedia' if key=='app' else 'AetherMediaTests','ReferencedContainer':'container:AetherMedia.xcodeproj'})
scheme=ET.Element('Scheme',{'LastUpgradeVersion':'1600','version':'1.3'})
build=ET.SubElement(scheme,'BuildAction',{'parallelizeBuildables':'YES','buildImplicitDependencies':'YES'})
entries=ET.SubElement(build,'BuildActionEntries')
entry=ET.SubElement(entries,'BuildActionEntry',dict(buildForTesting='YES',buildForRunning='YES',buildForProfiling='YES',buildForArchiving='YES',buildForAnalyzing='YES'));buildable(entry,'app','AetherMedia.app')
test=ET.SubElement(scheme,'TestAction',dict(buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',shouldUseLaunchSchemeArgsEnv='NO'))
testables=ET.SubElement(test,'Testables');target=ET.SubElement(testables,'TestableReference',{'skipped':'NO','parallelizable':'NO'});buildable(target,'test','AetherMediaTests.xctest')
env=ET.SubElement(test,'EnvironmentVariables');ET.SubElement(env,'EnvironmentVariable',dict(key='AETHERMEDIA_UNIT_TESTING',value='1',isEnabled='YES'))
launch=ET.SubElement(scheme,'LaunchAction',dict(buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',launchStyle='0',useCustomWorkingDirectory='NO',ignoresPersistentStateOnLaunch='NO',debugDocumentVersioning='YES',allowLocationSimulation='YES'))
run=ET.SubElement(launch,'BuildableProductRunnable',{'runnableDebuggingMode':'0'});buildable(run,'app','AetherMedia.app')
profile=ET.SubElement(scheme,'ProfileAction',dict(buildConfiguration='Release',shouldUseLaunchSchemeArgsEnv='YES',savedToolIdentifier='',useCustomWorkingDirectory='NO',debugDocumentVersioning='YES'));run=ET.SubElement(profile,'BuildableProductRunnable',{'runnableDebuggingMode':'0'});buildable(run,'app','AetherMedia.app')
ET.SubElement(scheme,'AnalyzeAction',{'buildConfiguration':'Debug'});ET.SubElement(scheme,'ArchiveAction',{'buildConfiguration':'Release','revealArchiveInOrganizer':'YES'})
ET.indent(scheme)
dest=project/'xcshareddata/xcschemes';dest.mkdir(parents=True,exist_ok=True)
ET.ElementTree(scheme).write(dest/'AetherMedia.xcscheme',encoding='utf-8',xml_declaration=True)
print(f'Generated iOS app target ({len(appfiles)} Swift files), hosted test target ({len(testfiles)} Swift files) and shared scheme.')
