#!/usr/bin/env python3
"""Generate a dependency-free Xcode project; shared core files stay in one place."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
project = root / 'iOS' / 'TheCursorConnect.xcodeproj'
project.mkdir(exist_ok=True)
text = '''// !$*UTF8*$!
{
 archiveVersion = 1;
 classes = {};
 objectVersion = 56;
 objects = {
  A00000000000000000000001 = {isa = PBXProject; attributes = {LastUpgradeCheck = 1600;}; buildConfigurationList = A00000000000000000000002; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base); mainGroup = A00000000000000000000003; productRefGroup = A00000000000000000000004; projectDirPath = ""; projectRoot = ""; targets = (A00000000000000000000005);};
  A00000000000000000000002 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000010, A00000000000000000000011); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
  A00000000000000000000003 = {isa = PBXGroup; children = (A00000000000000000000006, A00000000000000000000007, A00000000000000000000019, A00000000000000000000020, A00000000000000000000004); sourceTree = "<group>";};
  A00000000000000000000004 = {isa = PBXGroup; children = (A00000000000000000000008); name = Products; sourceTree = "<group>";};
  A00000000000000000000005 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000009; buildPhases = (A00000000000000000000012, A00000000000000000000013, A00000000000000000000014); buildRules = (); dependencies = (); name = TheCursorConnect; productName = TheCursorConnect; productReference = A00000000000000000000008; productType = "com.apple.product-type.application";};
  A00000000000000000000006 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = TheCursorConnect/TheCursorConnectApp.swift; sourceTree = "<group>";};
  A00000000000000000000007 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = Pairing.swift; path = ../Sources/CursorCore/Pairing.swift; sourceTree = "<group>";};
  A00000000000000000000008 = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = TheCursorConnect.app; sourceTree = BUILT_PRODUCTS_DIR;};
  A00000000000000000000009 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000015, A00000000000000000000016); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
  A00000000000000000000010 = {isa = XCBuildConfiguration; buildSettings = {CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0;}; name = Debug;};
  A00000000000000000000011 = {isa = XCBuildConfiguration; buildSettings = {CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0;}; name = Release;};
  A00000000000000000000012 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (A00000000000000000000017, A00000000000000000000018, A00000000000000000000021); runOnlyForDeploymentPostprocessing = 0;};
  A00000000000000000000013 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;};
  A00000000000000000000014 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (A00000000000000000000022); runOnlyForDeploymentPostprocessing = 0;};
  A00000000000000000000015 = {isa = XCBuildConfiguration; buildSettings = {SETTINGS SWIFT_OPTIMIZATION_LEVEL = "-Onone";}; name = Debug;};
  A00000000000000000000016 = {isa = XCBuildConfiguration; buildSettings = {SETTINGS SWIFT_OPTIMIZATION_LEVEL = "-O";}; name = Release;};
  A00000000000000000000017 = {isa = PBXBuildFile; fileRef = A00000000000000000000006;};
  A00000000000000000000018 = {isa = PBXBuildFile; fileRef = A00000000000000000000007;};
  A00000000000000000000019 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = WaterGlass.swift; path = ../Sources/CursorDesign/WaterGlass.swift; sourceTree = "<group>";};
  A00000000000000000000020 = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = TheCursorConnect/Assets.xcassets; sourceTree = "<group>";};
  A00000000000000000000021 = {isa = PBXBuildFile; fileRef = A00000000000000000000019;};
  A00000000000000000000022 = {isa = PBXBuildFile; fileRef = A00000000000000000000020;};
 };
 rootObject = A00000000000000000000001;
}
'''
settings = '''CODE_SIGN_STYLE = Automatic;
CURRENT_PROJECT_VERSION = 3;
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
GENERATE_INFOPLIST_FILE = YES;
INFOPLIST_FILE = TheCursorConnect/Info.plist;
INFOPLIST_KEY_CFBundleDisplayName = "The Cursor Connect";
INFOPLIST_KEY_NSCameraUsageDescription = "Scan the setup QR code displayed by The Cursor on your Mac.";
INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription = "Connect to The Cursor on your Mac to share screen dimensions and manage your pointer session.";
INFOPLIST_KEY_UILaunchScreen_Generation = YES;
INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
MARKETING_VERSION = 0.1.0;
PRODUCT_BUNDLE_IDENTIFIER = app.thecursor.connect;
PRODUCT_NAME = "$(TARGET_NAME)";
SWIFT_VERSION = 5.0;
TARGETED_DEVICE_FAMILY = 1;
'''
# Shared authenticated framing and the iOS 27 ScreenCaptureKit sender.
extra_files = [('../Sources/CursorCore/ScreenStreamProtocol.swift', 'ScreenStreamProtocol.swift'),
               ('TheCursorConnect/WirelessScreenShare.swift', 'WirelessScreenShare.swift')]
for index, (path, name) in enumerate(extra_files):
    file_id = f'B{index:023X}'
    build_id = f'C{index:023X}'
    text = text.replace('A00000000000000000000006, A00000000000000000000007', f'{file_id}, A00000000000000000000006, A00000000000000000000007')
    text = text.replace('A00000000000000000000017, A00000000000000000000018', f'{build_id}, A00000000000000000000017, A00000000000000000000018')
    text = text.replace(' };\n rootObject', f'  {file_id} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = {name}; path = {path}; sourceTree = "<group>";}};\n  {build_id} = {{isa = PBXBuildFile; fileRef = {file_id};}};\n }};\n rootObject')
(project / 'project.pbxproj').write_text(text.replace('SETTINGS', settings))
schemes = project / 'xcshareddata' / 'xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
(schemes / 'TheCursorConnect.xcscheme').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A00000000000000000000005" BuildableName="TheCursorConnect.app" BlueprintName="TheCursorConnect" ReferencedContainer="container:TheCursorConnect.xcodeproj"/>
</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A00000000000000000000005" BuildableName="TheCursorConnect.app" BlueprintName="TheCursorConnect" ReferencedContainer="container:TheCursorConnect.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release"/>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(project)
