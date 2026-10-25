#!/usr/bin/env python3
"""Generates Sunspot.xcodeproj.

The project file is generated rather than hand-edited so that adding a source file never
means touching build metadata. Xcode's synchronised folder groups (objectVersion 77) do the
rest: anything dropped into Sunspot/ or SunspotTests/ is picked up on the next build.

Run from the repository root:  python3 Tools/make-project.py
"""

from pathlib import Path

APP = "Sunspot"
BUNDLE_ID = "app.sunplot"
DEPLOYMENT_TARGET = "17.0"
SWIFT_VERSION = "6.0"
MARKETING_VERSION = "1.2"
# Apple developer team, needed to sign for a real device. Same account as Sunfold.
DEVELOPMENT_TEAM = "3M856J997X"

# Stable object ids. The prefix keeps them recognisably ours in diffs.
def oid(n: int) -> str:
    return f"5U{n:022X}"

IDS = {name: oid(i) for i, name in enumerate([
    "project", "mainGroup", "productsGroup", "appTarget", "testTarget",
    "appProduct", "testProduct", "appSourcesPhase", "appFrameworksPhase",
    "appResourcesPhase", "testSourcesPhase", "testFrameworksPhase",
    "appSyncGroup", "testSyncGroup", "projectConfigList", "appConfigList",
    "testConfigList", "projectDebug", "projectRelease", "appDebug", "appRelease",
    "testDebug", "testRelease", "localPackage", "solarProduct", "solarBuildFile",
    "testDependency", "testProxy", "solarProductTest", "solarBuildFileTest", "storekitFile", "storekitBuildFile", "testResourcesPhase", "widgetTarget", "widgetProduct", "widgetSyncGroup", "widgetSourcesPhase", "widgetFrameworksPhase", "widgetResourcesPhase", "widgetConfigList", "widgetDebug", "widgetRelease", "widgetDependency", "widgetProxy", "embedPhase", "widgetEmbedFile", "solarProductWidget", "solarBuildFileWidget", "widgetInfoFile", "appEntitlements", "widgetEntitlements", "spotProductApp", "spotBuildFileApp", "spotProductWidget", "spotBuildFileWidget", "spotProductTest", "spotBuildFileTest", "storekitAppBuildFile",
], start=1)}

I = IDS


def build_settings(pairs: dict) -> str:
    return "\n".join(f"\t\t\t\t{k} = {v};" for k, v in pairs.items())


PROJECT_COMMON = {
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": SWIFT_VERSION,
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
}

APP_COMMON = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CURRENT_PROJECT_VERSION": "3",
    "MARKETING_VERSION": MARKETING_VERSION,
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    # Portrait and nothing else. Landscape was declared and never once looked at: the Sky
    # screen's controls sit against the bottom of a tall frame, and an orientation nobody has
    # seen is an orientation a reviewer sees first. Locking it also keeps the camera preview
    # at a fixed rotation against the device, which is what lets the overlay be worked out
    # from the device's own attitude and stay lined up however the phone is held.
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": '"UIInterfaceOrientationPortrait"',
    "INFOPLIST_KEY_NSLocationWhenInUseUsageDescription": '"Sunplot needs your location to work out where the sun travels over this spot."',
    "INFOPLIST_KEY_NSCameraUsageDescription": '"Sunplot uses the camera so you can trace the roofs and trees around a spot."',
    # Required because the Sky screen reads the device's attitude. Without the key iOS ends
    # the process the moment the screen asks, with no dialog and no warning.
    "INFOPLIST_KEY_NSMotionUsageDescription": '"Sunplot reads which way the phone is pointing so the sun\'s path lines up with what the camera sees."',
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    # What the home screen calls it. The target, the folders and the bundle identifier still
    # read Sunspot and stay that way on purpose: none of them is ever shown to anybody, and a
    # purchase identifier cannot be renamed once it exists in App Store Connect — only
    # replaced by a different product. Everything a person actually reads says Sunplot.
    "INFOPLIST_KEY_CFBundleDisplayName": '"Sunplot"',
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    # iPhone only. The build declared iPad as well, which was never true of anything here:
    # the layouts are phone-shaped, nothing has been run on an iPad, and iPad defaults to all
    # four orientations while the Sky screen's projection has only ever been exercised in
    # portrait. Claiming it also makes an iPad screenshot set mandatory in App Store Connect
    # and puts the app in front of a reviewer on hardware it was not built for. One character
    # to put back, on the day it is actually wanted and tested.
    "TARGETED_DEVICE_FAMILY": "1",
    # Otherwise every upload stops to ask the export compliance question by hand. The answer
    # is no: the app makes no network requests of its own and uses nothing beyond the
    # encryption inside Apple's own frameworks.
    "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "NO",
    "CODE_SIGN_STYLE": "Automatic",
    "DEVELOPMENT_TEAM": DEVELOPMENT_TEAM,
    "CODE_SIGN_ENTITLEMENTS": f"Config/{APP}.entitlements",
}

WIDGET_COMMON = {
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CURRENT_PROJECT_VERSION": "3",
    "MARKETING_VERSION": MARKETING_VERSION,
    # A widget extension needs a real Info.plist: its NSExtension entry is a nested
    # dictionary, and the generated-plist build settings cannot express one.
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": f"Config/{APP}Widgets-Info.plist",
    "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.widgets",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SKIP_INSTALL": "YES",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "TARGETED_DEVICE_FAMILY": "1",
    "CODE_SIGN_STYLE": "Automatic",
    "DEVELOPMENT_TEAM": DEVELOPMENT_TEAM,
    "CODE_SIGN_ENTITLEMENTS": f"Config/{APP}Widgets.entitlements",
}

TEST_COMMON = {
    "BUNDLE_LOADER": '"$(TEST_HOST)"',
    "GENERATE_INFOPLIST_FILE": "YES",
    "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.tests",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    # Matching the host: a test bundle that claims a device family its host does not is a
    # mismatch waiting to be reported on some future Xcode.
    "TARGETED_DEVICE_FAMILY": "1",
    "TEST_HOST": f'"$(BUILT_PRODUCTS_DIR)/{APP}.app/{APP}"',
    "CODE_SIGN_STYLE": "Automatic",
    "DEVELOPMENT_TEAM": DEVELOPMENT_TEAM,
    # StoreKitTest is not part of the ordinary SDK link; without it SKTestSession is simply
    # not in scope and a purchase can only ever be exercised by hand.
    "OTHER_LDFLAGS": '"-framework StoreKitTest"',
}

pbxproj = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
		{I['solarBuildFile']} /* SolarCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['solarProduct']} /* SolarCore */; }};
		{I['solarBuildFileTest']} /* SolarCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['solarProductTest']} /* SolarCore */; }};
		{I['storekitBuildFile']} /* {APP}.storekit in Resources */ = {{isa = PBXBuildFile; fileRef = {I['storekitFile']} /* {APP}.storekit */; }};
		{I['solarBuildFileWidget']} /* SolarCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['solarProductWidget']} /* SolarCore */; }};
		{I['spotBuildFileApp']} /* SpotKit in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['spotProductApp']} /* SpotKit */; }};
		{I['spotBuildFileWidget']} /* SpotKit in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['spotProductWidget']} /* SpotKit */; }};
		{I['spotBuildFileTest']} /* SpotKit in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['spotProductTest']} /* SpotKit */; }};
		{I['widgetEmbedFile']} /* {APP}Widgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {I['widgetProduct']} /* {APP}Widgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{I['widgetProxy']} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {I['project']} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {I['widgetTarget']};
			remoteInfo = {APP}Widgets;
		}};
		{I['testProxy']} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {I['project']} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {I['appTarget']};
			remoteInfo = {APP};
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
		{I['appProduct']} /* {APP}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP}.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['testProduct']} /* {APP}Tests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {APP}Tests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['storekitFile']} /* {APP}.storekit */ = {{isa = PBXFileReference; lastKnownFileType = text; name = {APP}.storekit; path = Config/{APP}.storekit; sourceTree = "<group>"; }};
		{I['widgetProduct']} /* {APP}Widgets.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = {APP}Widgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['widgetInfoFile']} /* {APP}Widgets-Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; name = "{APP}Widgets-Info.plist"; path = "Config/{APP}Widgets-Info.plist"; sourceTree = "<group>"; }};
		{I['appEntitlements']} /* {APP}.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; name = {APP}.entitlements; path = Config/{APP}.entitlements; sourceTree = "<group>"; }};
		{I['widgetEntitlements']} /* {APP}Widgets.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; name = {APP}Widgets.entitlements; path = Config/{APP}Widgets.entitlements; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{I['appSyncGroup']} /* {APP} */ = {{isa = PBXFileSystemSynchronizedRootGroup; explicitFileTypes = {{}}; explicitFolders = (); path = {APP}; sourceTree = "<group>"; }};
		{I['widgetSyncGroup']} /* {APP}Widgets */ = {{isa = PBXFileSystemSynchronizedRootGroup; explicitFileTypes = {{}}; explicitFolders = (); path = {APP}Widgets; sourceTree = "<group>"; }};
		{I['testSyncGroup']} /* {APP}Tests */ = {{isa = PBXFileSystemSynchronizedRootGroup; explicitFileTypes = {{}}; explicitFolders = (); path = {APP}Tests; sourceTree = "<group>"; }};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		{I['appFrameworksPhase']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{I['solarBuildFile']} /* SolarCore in Frameworks */,
				{I['spotBuildFileApp']} /* SpotKit in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['widgetFrameworksPhase']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{I['solarBuildFileWidget']} /* SolarCore in Frameworks */,
				{I['spotBuildFileWidget']} /* SpotKit in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['testFrameworksPhase']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{I['solarBuildFileTest']} /* SolarCore in Frameworks */,
				{I['spotBuildFileTest']} /* SpotKit in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{I['mainGroup']} = {{
			isa = PBXGroup;
			children = (
				{I['appSyncGroup']} /* {APP} */,
				{I['widgetSyncGroup']} /* {APP}Widgets */,
				{I['testSyncGroup']} /* {APP}Tests */,
				{I['storekitFile']} /* {APP}.storekit */,
				{I['widgetInfoFile']} /* {APP}Widgets-Info.plist */,
				{I['appEntitlements']} /* {APP}.entitlements */,
				{I['widgetEntitlements']} /* {APP}Widgets.entitlements */,
				{I['productsGroup']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{I['productsGroup']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{I['appProduct']} /* {APP}.app */,
				{I['testProduct']} /* {APP}Tests.xctest */,
				{I['widgetProduct']} /* {APP}Widgets.appex */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{I['appTarget']} /* {APP} */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['appConfigList']} /* Build configuration list for PBXNativeTarget "{APP}" */;
			buildPhases = (
				{I['appSourcesPhase']} /* Sources */,
				{I['appFrameworksPhase']} /* Frameworks */,
				{I['appResourcesPhase']} /* Resources */,
				{I['embedPhase']} /* Embed Foundation Extensions */,
			);
			buildRules = (
			);
			dependencies = (
				{I['widgetDependency']} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{I['appSyncGroup']} /* {APP} */,
			);
			name = {APP};
			packageProductDependencies = (
				{I['solarProduct']} /* SolarCore */,
				{I['spotProductApp']} /* SpotKit */,
			);
			productName = {APP};
			productReference = {I['appProduct']} /* {APP}.app */;
			productType = "com.apple.product-type.application";
		}};
		{I['widgetTarget']} /* {APP}Widgets */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['widgetConfigList']} /* Build configuration list for PBXNativeTarget "{APP}Widgets" */;
			buildPhases = (
				{I['widgetSourcesPhase']} /* Sources */,
				{I['widgetFrameworksPhase']} /* Frameworks */,
				{I['widgetResourcesPhase']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{I['widgetSyncGroup']} /* {APP}Widgets */,
			);
			name = {APP}Widgets;
			packageProductDependencies = (
				{I['solarProductWidget']} /* SolarCore */,
				{I['spotProductWidget']} /* SpotKit */,
			);
			productName = {APP}Widgets;
			productReference = {I['widgetProduct']} /* {APP}Widgets.appex */;
			productType = "com.apple.product-type.app-extension";
		}};
		{I['testTarget']} /* {APP}Tests */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['testConfigList']} /* Build configuration list for PBXNativeTarget "{APP}Tests" */;
			buildPhases = (
				{I['testSourcesPhase']} /* Sources */,
				{I['testFrameworksPhase']} /* Frameworks */,
				{I['testResourcesPhase']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				{I['testDependency']} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{I['testSyncGroup']} /* {APP}Tests */,
			);
			name = {APP}Tests;
			packageProductDependencies = (
				{I['solarProductTest']} /* SolarCore */,
				{I['spotProductTest']} /* SpotKit */,
			);
			productName = {APP}Tests;
			productReference = {I['testProduct']} /* {APP}Tests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{I['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2660;
				LastUpgradeCheck = 2660;
				TargetAttributes = {{
					{I['appTarget']} = {{
						CreatedOnToolsVersion = 26.6;
					}};
					{I['widgetTarget']} = {{
						CreatedOnToolsVersion = 26.6;
					}};
					{I['testTarget']} = {{
						CreatedOnToolsVersion = 26.6;
						TestTargetID = {I['appTarget']};
					}};
				}};
			}};
			buildConfigurationList = {I['projectConfigList']} /* Build configuration list for PBXProject "{APP}" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				de,
				es,
				fr,
				it,
				ja,
				ko,
				nl,
				pl,
				"pt-BR",
				ru,
				tr,
				"zh-Hans",
				"zh-Hant",
				Base,
			);
			mainGroup = {I['mainGroup']};
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				{I['localPackage']} /* XCLocalSwiftPackageReference "Packages/SolarCore" */,
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = {I['productsGroup']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{I['appTarget']} /* {APP} */,
				{I['widgetTarget']} /* {APP}Widgets */,
				{I['testTarget']} /* {APP}Tests */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{I['appResourcesPhase']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['widgetResourcesPhase']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['testResourcesPhase']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{I['storekitBuildFile']} /* {APP}.storekit in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{I['appSourcesPhase']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['widgetSourcesPhase']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['testSourcesPhase']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXCopyFilesBuildPhase section */
		{I['embedPhase']} /* Embed Foundation Extensions */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				{I['widgetEmbedFile']} /* {APP}Widgets.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXTargetDependency section */
		{I['widgetDependency']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {I['widgetTarget']} /* {APP}Widgets */;
			targetProxy = {I['widgetProxy']} /* PBXContainerItemProxy */;
		}};
		{I['testDependency']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {I['appTarget']} /* {APP} */;
			targetProxy = {I['testProxy']} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		{I['projectDebug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{build_settings({**PROJECT_COMMON, "DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "GCC_OPTIMIZATION_LEVEL": "0", "ONLY_ACTIVE_ARCH": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"', "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"'})}
			}};
			name = Debug;
		}};
		{I['projectRelease']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{build_settings({**PROJECT_COMMON, "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"', "ENABLE_NS_ASSERTIONS": "NO", "SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES"})}
			}};
			name = Release;
		}};
		{I['appDebug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{build_settings(APP_COMMON)}
			}};
			name = Debug;
		}};
		{I['appRelease']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{build_settings(APP_COMMON)}
			}};
			name = Release;
		}};
		{I['widgetDebug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{build_settings(WIDGET_COMMON)}
			}};
			name = Debug;
		}};
		{I['widgetRelease']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{build_settings(WIDGET_COMMON)}
			}};
			name = Release;
		}};
		{I['testDebug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{build_settings(TEST_COMMON)}
			}};
			name = Debug;
		}};
		{I['testRelease']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{build_settings(TEST_COMMON)}
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{I['projectConfigList']} /* Build configuration list for PBXProject "{APP}" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['projectDebug']} /* Debug */,
				{I['projectRelease']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{I['appConfigList']} /* Build configuration list for PBXNativeTarget "{APP}" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['appDebug']} /* Debug */,
				{I['appRelease']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{I['widgetConfigList']} /* Build configuration list for PBXNativeTarget "{APP}Widgets" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['widgetDebug']} /* Debug */,
				{I['widgetRelease']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{I['testConfigList']} /* Build configuration list for PBXNativeTarget "{APP}Tests" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['testDebug']} /* Debug */,
				{I['testRelease']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		{I['localPackage']} /* XCLocalSwiftPackageReference "Packages/SolarCore" */ = {{
			isa = XCLocalSwiftPackageReference;
			relativePath = Packages/SolarCore;
		}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		{I['solarProduct']} /* SolarCore */ = {{
			isa = XCSwiftPackageProductDependency;
			productName = SolarCore;
		}};
		{I['solarProductTest']} /* SolarCore */ = {{
			isa = XCSwiftPackageProductDependency;
			productName = SolarCore;
		}};
		{I['solarProductWidget']} /* SolarCore */ = {{
			isa = XCSwiftPackageProductDependency;
			productName = SolarCore;
		}};
		{I['spotProductApp']} /* SpotKit */ = {{isa = XCSwiftPackageProductDependency; productName = SpotKit; }};
		{I['spotProductWidget']} /* SpotKit */ = {{isa = XCSwiftPackageProductDependency; productName = SpotKit; }};
		{I['spotProductTest']} /* SpotKit */ = {{isa = XCSwiftPackageProductDependency; productName = SpotKit; }};
/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = {I['project']} /* Project object */;
}}
"""

# The scheme, byte for byte as Xcode itself writes it.
#
# Not a formatting preference. Xcode rewrites this file into its own canonical shape the
# first time anybody opens Edit Scheme, so a generator that emits a tidier version guarantees
# a diff after every visit to the scheme editor, and guarantees that regenerating undoes
# whatever Xcode just wrote. Matching it exactly makes regeneration a no-op.
#
# It is also the likeliest reason the StoreKit configuration had to be chosen by hand after
# every regeneration. The path below has always been correct; what changed under Xcode was
# the file around it. This does not promise the one-time click is gone — only a real Xcode
# run can say — but there is now nothing for Xcode to notice.
#
# The explanation lives here rather than as an XML comment in the scheme because Xcode
# deletes XML comments when it rewrites the file, which is exactly what happened to the last
# one. Tools/check.sh asserts that the file this names is actually on disk.
SCHEME = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2660"
   version = "1.3">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{I['appTarget']}"
               BuildableName = "{APP}.app"
               BlueprintName = "{APP}"
               ReferencedContainer = "container:{APP}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{I['testTarget']}"
               BuildableName = "{APP}Tests.xctest"
               BlueprintName = "{APP}Tests"
               ReferencedContainer = "container:{APP}.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{I['appTarget']}"
            BuildableName = "{APP}.app"
            BlueprintName = "{APP}"
            ReferencedContainer = "container:{APP}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
      <StoreKitConfigurationFileReference
         identifier = "../../Config/{APP}.storekit">
      </StoreKitConfigurationFileReference>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{I['appTarget']}"
            BuildableName = "{APP}.app"
            BlueprintName = "{APP}"
            ReferencedContainer = "container:{APP}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

root = Path(__file__).resolve().parent.parent
project_dir = root / f"{APP}.xcodeproj"
scheme_dir = project_dir / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
(project_dir / "project.pbxproj").write_text(pbxproj, encoding="utf-8")
(scheme_dir / f"{APP}.xcscheme").write_text(SCHEME, encoding="utf-8")
print(f"wrote {project_dir.relative_to(root)}")
