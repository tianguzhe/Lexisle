#!/usr/bin/env python3
"""Generate a self-contained Xcode project; run again after adding Swift files.

Uses only Python's standard library, avoiding a global XcodeGen dependency.
"""
from pathlib import Path
import hashlib
import json
import re
import copy
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
brand_configuration = (ROOT / "Config/Brand.xcconfig").read_text()
brand_product = re.search(r"^APP_ENGLISH_NAME\s*=\s*([A-Za-z][A-Za-z0-9_-]*)\s*$", brand_configuration, re.MULTILINE)
if not brand_product:
    raise ValueError("Config/Brand.xcconfig must define APP_ENGLISH_NAME as an ASCII product name")
APP_PRODUCT_NAME = brand_product.group(1)
APP_BUNDLE_NAME = APP_PRODUCT_NAME + ".app"
PROJECT = ROOT / "WordAtlas.xcodeproj"
PROJECT.mkdir(exist_ok=True)
objects = {}

def identifier(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def add(object_key, **value):
    key = identifier(object_key)
    objects[key] = value
    return key

def plist(value, indent=0):
    pad = "\t" * indent
    if isinstance(value, dict):
        lines = ["{"]
        lines += ["\t" * (indent + 1) + json.dumps(str(k)) + " = " + plist(v, indent + 1) + ";" for k, v in value.items()]
        return "\n".join(lines) + "\n" + pad + "}"
    if isinstance(value, list):
        return "(\n" + "".join("\t" * (indent + 1) + plist(v, indent + 1) + ",\n" for v in value) + pad + ")"
    return json.dumps(str(value), ensure_ascii=False)

def ref(path, filetype):
    return add("file:" + path, isa="PBXFileReference", lastKnownFileType=filetype, path=path, sourceTree="SOURCE_ROOT")

sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "App").rglob("*.swift"))
test_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "Tests").rglob("*.swift"))
source_refs = [ref(p, "sourcecode.swift") for p in sources]
test_refs = [ref(p, "sourcecode.swift") for p in test_sources]
ui_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "UITests").rglob("*.swift"))
ui_refs = [ref(p, "sourcecode.swift") for p in ui_sources]
resources = ["App/Resources/Assets.xcassets"] + sorted(str(p.relative_to(ROOT)) for p in (ROOT / "App/Resources").iterdir() if p.is_file())
resource_refs = [ref(p, "folder.assetcatalog" if p.endswith(".xcassets") else "text.json" if p.endswith(".json") else "text") for p in resources]
config_refs = [ref(str(p.relative_to(ROOT)), "text.xcconfig" if p.suffix == ".xcconfig" else "text.plist.xml") for p in sorted((ROOT / "Config").iterdir()) if p.is_file() and p.name != "Developer.xcconfig"]
local_config = identifier("file:Config/Local.xcconfig")
cloud_config = identifier("file:Config/Cloud.xcconfig")
package = add("package:FSRS", isa="XCLocalSwiftPackageReference", relativePath="Vendor/swift-fsrs")

def build_files(label, references):
    return [add("build:" + label + ":" + reference, isa="PBXBuildFile", fileRef=reference) for reference in references]

def phase(label, isa, files):
    return add("phase:" + label, isa=isa, buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0)

names = ["Debug", "Release", "CloudDebug", "CloudRelease"]
project_configs = []
for name in names:
    debug = name.endswith("Debug")
    settings = {
        "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES", "COPY_PHASE_STRIP": "NO", "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17", "GCC_NO_COMMON_BLOCKS": "YES", "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete", "SWIFT_DEFAULT_ACTOR_ISOLATION": "nonisolated",
        "SWIFT_EMIT_LOC_STRINGS": "YES", "IPHONEOS_DEPLOYMENT_TARGET": "26.0", "MACOSX_DEPLOYMENT_TARGET": "26.0",
        "DEBUG_INFORMATION_FORMAT": "dwarf" if debug else "dwarf-with-dsym", "ENABLE_TESTABILITY": "YES" if debug else "NO",
        "GCC_OPTIMIZATION_LEVEL": "0" if debug else "s", "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if debug else "-O",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)" if debug else "$(inherited)",
        "ONLY_ACTIVE_ARCH": "YES" if debug else "NO",
    }
    project_configs.append(add("config:project:" + name, isa="XCBuildConfiguration", buildSettings=settings, name=name))
project_config_list = add("configs:project", isa="XCConfigurationList", buildConfigurations=project_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")
targets, products, target_attributes, scheme_details = [], [], {}, []

for platform in ["iOS", "macOS"]:
    mac = platform == "macOS"
    target_name = "WordAtlas-" + platform
    target_id = identifier("target:" + target_name)
    test_name = "WordAtlasTests-" + platform
    test_id = identifier("target:" + test_name)
    product = add("product:" + target_name, isa="PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path=APP_BUNDLE_NAME, sourceTree="BUILT_PRODUCTS_DIR")
    test_product = add("product:" + test_name, isa="PBXFileReference", explicitFileType="wrapper.cfbundle", includeInIndex=0, path=test_name + ".xctest", sourceTree="BUILT_PRODUCTS_DIR")
    products += [product, test_product]
    package_product = add("package-product:" + target_name, isa="XCSwiftPackageProductDependency", package=package, productName="FSRS")
    package_build = add("package-build:" + target_name, isa="PBXBuildFile", productRef=package_product)
    test_package_product = add("package-product:" + test_name, isa="XCSwiftPackageProductDependency", package=package, productName="FSRS")
    test_package_build = add("package-build:" + test_name, isa="PBXBuildFile", productRef=test_package_product)
    app_phases = [
        phase(target_name + ":sources", "PBXSourcesBuildPhase", build_files(target_name, source_refs)),
        phase(target_name + ":frameworks", "PBXFrameworksBuildPhase", [package_build]),
        phase(target_name + ":resources", "PBXResourcesBuildPhase", build_files(target_name, resource_refs)),
    ]
    test_phases = [
        phase(test_name + ":sources", "PBXSourcesBuildPhase", build_files(test_name, test_refs)),
        phase(test_name + ":frameworks", "PBXFrameworksBuildPhase", [test_package_build]),
        phase(test_name + ":resources", "PBXResourcesBuildPhase", []),
    ]
    app_configs, test_configs = [], []
    for name in names:
        cloud = name.startswith("Cloud")
        settings = {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0.0", "GENERATE_INFOPLIST_FILE": "NO",
            "INFOPLIST_FILE": "Config/" + platform + "-Info.plist", "PRODUCT_MODULE_NAME": "WordAtlas", "PRODUCT_NAME": "$(APP_ENGLISH_NAME)",
            "PRODUCT_BUNDLE_IDENTIFIER": "$(WORD_ATLAS_BUNDLE_PREFIX)" + (".mac" if mac else ""),
            "SDKROOT": "macosx" if mac else "iphoneos", "SUPPORTED_PLATFORMS": "macosx" if mac else "iphoneos iphonesimulator",
            "SWIFT_EMIT_LOC_STRINGS": "YES", "ENABLE_PREVIEWS": "YES",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks" if mac else "@executable_path/Frameworks"],
            "APS_ENVIRONMENT": "production" if name == "CloudRelease" else "development",
        }
        if mac:
            settings.update({"COMBINE_HIDPI_IMAGES": "YES", "ENABLE_APP_SANDBOX": "YES", "ENABLE_HARDENED_RUNTIME": "YES", "CODE_SIGN_ENTITLEMENTS": "Config/macOS-Cloud.entitlements" if cloud else "Config/macOS.entitlements"})
            if not cloud:
                settings["CODE_SIGN_IDENTITY"] = "-"
        else:
            settings.update({"TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO"})
            if cloud:
                settings["CODE_SIGN_ENTITLEMENTS"] = "Config/iOS.entitlements"
            else:
                settings["CODE_SIGNING_ALLOWED"] = "NO"
        app_configs.append(add("config:" + target_name + ":" + name, isa="XCBuildConfiguration", baseConfigurationReference=cloud_config if cloud else local_config, buildSettings=settings, name=name))
        tests = {
            "GENERATE_INFOPLIST_FILE": "YES", "PRODUCT_NAME": test_name, "PRODUCT_MODULE_NAME": "WordAtlasTests",
            "PRODUCT_BUNDLE_IDENTIFIER": "$(WORD_ATLAS_BUNDLE_PREFIX).tests." + platform.lower(),
            "SDKROOT": "macosx" if mac else "iphoneos", "SUPPORTED_PLATFORMS": "macosx" if mac else "iphoneos iphonesimulator",
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/$(APP_ENGLISH_NAME).app/" + ("Contents/MacOS/" if mac else "") + "$(APP_ENGLISH_NAME)",
            "BUNDLE_LOADER": "$(TEST_HOST)", "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@loader_path/Frameworks", "@executable_path/../Frameworks" if mac else "@executable_path/Frameworks"],
        }
        if mac and not cloud:
            tests["CODE_SIGN_IDENTITY"] = "-"
        elif not cloud:
            tests["CODE_SIGNING_ALLOWED"] = "NO"
        if not mac:
            tests["TARGETED_DEVICE_FAMILY"] = "1,2"
        test_configs.append(add("config:" + test_name + ":" + name, isa="XCBuildConfiguration", baseConfigurationReference=cloud_config if cloud else local_config, buildSettings=tests, name=name))
    app_config_list = add("configs:" + target_name, isa="XCConfigurationList", buildConfigurations=app_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")
    test_config_list = add("configs:" + test_name, isa="XCConfigurationList", buildConfigurations=test_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")
    proxy = add("proxy:" + test_name, isa="PBXContainerItemProxy", containerPortal=identifier("project"), proxyType=1, remoteGlobalIDString=target_id, remoteInfo=target_name)
    dependency = add("dependency:" + test_name, isa="PBXTargetDependency", target=target_id, targetProxy=proxy)
    add("target:" + target_name, isa="PBXNativeTarget", buildConfigurationList=app_config_list, buildPhases=app_phases, buildRules=[], dependencies=[], name=target_name, packageProductDependencies=[package_product], productName=APP_PRODUCT_NAME, productReference=product, productType="com.apple.product-type.application")
    add("target:" + test_name, isa="PBXNativeTarget", buildConfigurationList=test_config_list, buildPhases=test_phases, buildRules=[], dependencies=[dependency], name=test_name, packageProductDependencies=[test_package_product], productName=test_name, productReference=test_product, productType="com.apple.product-type.bundle.unit-test")
    targets += [target_id, test_id]
    target_attributes[target_id] = {"CreatedOnToolsVersion": "27.2"}
    target_attributes[test_id] = {"CreatedOnToolsVersion": "27.2", "TestTargetID": target_id}
    scheme_details.append((target_name, target_id, test_name, test_id))

ui_name = "WordAtlasUITests"
ui_id = identifier("target:" + ui_name)
ui_product = add("product:" + ui_name, isa="PBXFileReference", explicitFileType="wrapper.cfbundle", includeInIndex=0, path=ui_name + ".xctest", sourceTree="BUILT_PRODUCTS_DIR")
products.append(ui_product)
ui_configs = []
for name in names:
    cloud = name.startswith("Cloud")
    settings = {"GENERATE_INFOPLIST_FILE": "YES", "PRODUCT_NAME": ui_name, "PRODUCT_MODULE_NAME": ui_name,
                "PRODUCT_BUNDLE_IDENTIFIER": "$(WORD_ATLAS_BUNDLE_PREFIX).uitests", "SDKROOT": "iphoneos",
                "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "TARGETED_DEVICE_FAMILY": "1,2",
                "TEST_TARGET_NAME": "WordAtlas-iOS", "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES": "YES",
                "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"]}
    if not cloud:
        settings["CODE_SIGNING_ALLOWED"] = "NO"
    ui_configs.append(add("config:" + ui_name + ":" + name, isa="XCBuildConfiguration", baseConfigurationReference=cloud_config if cloud else local_config, buildSettings=settings, name=name))
ui_config_list = add("configs:" + ui_name, isa="XCConfigurationList", buildConfigurations=ui_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")
ui_proxy = add("proxy:" + ui_name, isa="PBXContainerItemProxy", containerPortal=identifier("project"), proxyType=1, remoteGlobalIDString=identifier("target:WordAtlas-iOS"), remoteInfo="WordAtlas-iOS")
ui_dependency = add("dependency:" + ui_name, isa="PBXTargetDependency", target=identifier("target:WordAtlas-iOS"), targetProxy=ui_proxy)
ui_phases = [phase(ui_name + ":sources", "PBXSourcesBuildPhase", build_files(ui_name, ui_refs)), phase(ui_name + ":frameworks", "PBXFrameworksBuildPhase", []), phase(ui_name + ":resources", "PBXResourcesBuildPhase", [])]
add("target:" + ui_name, isa="PBXNativeTarget", buildConfigurationList=ui_config_list, buildPhases=ui_phases, buildRules=[], dependencies=[ui_dependency], name=ui_name, productName=ui_name, productReference=ui_product, productType="com.apple.product-type.bundle.ui-testing")
targets.append(ui_id)
target_attributes[ui_id] = {"CreatedOnToolsVersion": "27.2", "TestTargetID": identifier("target:WordAtlas-iOS")}

def source_group(directory, paths):
    """Mirror source directories in Xcode while file references remain SOURCE_ROOT-relative."""
    prefix = directory + "/"
    folders = sorted({path[len(prefix):].split("/")[0] for path in paths if "/" in path[len(prefix):]})
    children = [source_group(prefix + folder, [path for path in paths if path.startswith(prefix + folder + "/")]) for folder in folders]
    children += [identifier("file:" + path) for path in paths if "/" not in path[len(prefix):]]
    return add("group:" + directory, isa="PBXGroup", children=children, name=Path(directory).name, sourceTree="<group>")

app_group = source_group("App", sources)
resource_group = add("group:Resources", isa="PBXGroup", children=resource_refs, name="Resources", sourceTree="<group>")
tests_group = add("group:Tests", isa="PBXGroup", children=test_refs, name="Tests", sourceTree="<group>")
ui_group = add("group:UITests", isa="PBXGroup", children=ui_refs, name="UITests", sourceTree="<group>")
config_group = add("group:Config", isa="PBXGroup", children=config_refs, name="Config", sourceTree="<group>")
product_group = add("group:Products", isa="PBXGroup", children=products, name="Products", sourceTree="<group>")
main_group = add("group:Main", isa="PBXGroup", children=[app_group, resource_group, tests_group, ui_group, config_group, product_group], sourceTree="<group>")
root = add("project", isa="PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastSwiftUpdateCheck": "2720", "LastUpgradeCheck": "2720", "TargetAttributes": target_attributes}, buildConfigurationList=project_config_list, compatibilityVersion="Xcode 14.0", developmentRegion="zh-Hans", hasScannedForEncodings=0, knownRegions=["zh-Hans", "en", "Base"], mainGroup=main_group, packageReferences=[package], productRefGroup=product_group, projectDirPath="", projectRoot="", targets=targets)
project = {"archiveVersion": 1, "classes": {}, "objectVersion": 60, "objects": objects, "rootObject": root}
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + plist(project) + "\n")

scheme_dir = PROJECT / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
def buildable(parent, target_name, target_id, product_name):
    ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=target_id, BuildableName=product_name, BlueprintName=target_name, ReferencedContainer="container:WordAtlas.xcodeproj")
for target_name, target_id, test_name, test_id in scheme_details:
    for cloud in [False, True]:
        config = "CloudDebug" if cloud else "Debug"
        scheme = ET.Element("Scheme", LastUpgradeVersion="2720", version="1.7")
        build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
        entries = ET.SubElement(build, "BuildActionEntries")
        entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES", buildForProfiling="YES", buildForArchiving="YES", buildForAnalyzing="YES")
        buildable(entry, target_name, target_id, APP_BUNDLE_NAME)
        tests = ET.SubElement(scheme, "TestAction", buildConfiguration=config, selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES", codeCoverageEnabled="YES")
        testables = ET.SubElement(tests, "Testables")
        testable = ET.SubElement(testables, "TestableReference", skipped="NO", parallelizable="NO")
        buildable(testable, test_name, test_id, test_name + ".xctest")
        launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration=config, selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", allowLocationSimulation="YES")
        runnable = ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0")
        buildable(runnable, target_name, target_id, APP_BUNDLE_NAME)
        profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="CloudRelease" if cloud else "Release", shouldUseLaunchSchemeArgsEnv="YES", savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
        runnable = ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0")
        buildable(runnable, target_name, target_id, APP_BUNDLE_NAME)
        ET.SubElement(scheme, "AnalyzeAction", buildConfiguration=config)
        ET.SubElement(scheme, "ArchiveAction", buildConfiguration="CloudRelease" if cloud else "Release", revealArchiveInOrganizer="YES")
        ET.indent(scheme, space="   ")
        ET.ElementTree(scheme).write(scheme_dir / (target_name + ("-Cloud" if cloud else "") + ".xcscheme"), encoding="UTF-8", xml_declaration=True)
        if target_name == "WordAtlas-iOS" and not cloud:
            ui_scheme = copy.deepcopy(scheme)
            testables = ui_scheme.find("TestAction/Testables")
            testables.clear()
            testable = ET.SubElement(testables, "TestableReference", skipped="NO", parallelizable="NO")
            buildable(testable, ui_name, ui_id, ui_name + ".xctest")
            ET.indent(ui_scheme, space="   ")
            ET.ElementTree(ui_scheme).write(scheme_dir / "WordAtlas-UI-Tests.xcscheme", encoding="UTF-8", xml_declaration=True)
print("Generated WordAtlas.xcodeproj:", len(sources), "app sources,", len(test_sources), "test sources; iOS and native macOS.")
