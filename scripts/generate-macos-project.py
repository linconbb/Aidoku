#!/usr/bin/env python3
"""Generate isolated native macOS target; do not change the upstream iOS project."""
from pathlib import Path
import hashlib, json
shared = [
    "Aidoku/Core/Sources/BuiltIn/Local/LocalFileNameParser.swift",
    "Aidoku/Extensions/ZIPFoundation/Archive.swift",
    "Aidoku/Core/Utilities/SemanticVersion.swift",
    "Aidoku/Core/Sources/SourceList/SourceList.swift",
    "Aidoku/Core/Sources/SourceList/ExternalSourceInfo.swift",
    "Aidoku/Core/Sources/SourceInfo.swift",
]
sources = sorted(str(p) for group in ("App", "Core", "Features") for p in Path("macOS", group).rglob("*.swift")) + shared
ident = lambda name: hashlib.sha256(name.encode()).hexdigest()[:24].upper()
objects = []
def obj(name, fields):
    objects.append(f"{ident(name)} = {{ {fields} }};")
    return ident(name)
refs, builds = [], []
for source in sources:
    refs.append(obj(source, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{source}"; sourceTree = SOURCE_ROOT;'))
    builds.append(obj("build"+source, f"isa = PBXBuildFile; fileRef = {ident(source)};"))
icon = obj("icon", 'isa = PBXFileReference; lastKnownFileType = image.icns; path = "macOS/Resources/AppIcon.icns"; sourceTree = SOURCE_ROOT;')
refs.append(icon)
iconbuild = obj("iconbuild", f'isa = PBXBuildFile; fileRef = {icon};')
config = obj("config", 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = "macOS/Aidoku-MACOS.xcconfig"; sourceTree = SOURCE_ROOT;')
product = obj("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Aidoku.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = obj("products", f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
group = obj("group", f'isa = PBXGroup; children = ({",".join(refs+[config,products])},); sourceTree = "<group>";')
sourcesphase = obj("sources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
packages, dependencies, links = [], [], []
for name,url,revision in [
    ("ZIPFoundation", "https://github.com/weichsel/ZIPFoundation.git", "22787ffb59de99e5dc1fbfe80b19c97a904ad48d"),
    ("AidokuRunner", "https://github.com/Aidoku/AidokuRunner", "cc4d06ff399e7169b9c647bccede7cb29bc805c6"),
]:
    pkg = obj(name+"package", f'isa = XCRemoteSwiftPackageReference; repositoryURL = "{url}"; requirement = {{kind = revision; revision = {revision};}};')
    dep = obj(name+"product", f'isa = XCSwiftPackageProductDependency; package = {pkg}; productName = {name};')
    packages.append(pkg); dependencies.append(dep)
    links.append(obj(name+"link", f'isa = PBXBuildFile; productRef = {dep};'))
frameworks = obj("frameworks", f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({",".join(links)},); runOnlyForDeploymentPostprocessing = 0;')
resources = obj("resources", f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({iconbuild},); runOnlyForDeploymentPostprocessing = 0;')
for kind in ["project","target"]:
    configs=[]
    for mode in ["Debug","Release"]:
        settings = 'SWIFT_OPTIMIZATION_LEVEL = "-Onone";' if mode == "Debug" else 'SWIFT_OPTIMIZATION_LEVEL = "-O"; SWIFT_COMPILATION_MODE = wholemodule;'
        configs.append(obj(kind+mode, 'isa = XCBuildConfiguration; ' + (f'baseConfigurationReference = {config}; ' if kind == "target" else '') + f'buildSettings = {{{settings}}}; name = {mode};'))
    obj(kind+"configs", f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = obj("target", f'isa = PBXNativeTarget; name = "Aidoku-macOS"; productName = Aidoku; productReference = {product}; productType = "com.apple.product-type.application"; buildConfigurationList = {ident("targetconfigs")}; buildPhases = ({sourcesphase},{frameworks},{resources},); buildRules = (); dependencies = (); packageProductDependencies = ({",".join(dependencies)},);')
project = obj("project", f'isa = PBXProject; attributes = {{LastUpgradeCheck = 1600;}}; buildConfigurationList = {ident("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en,Base,); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},); packageReferences = ({",".join(packages)},);')
p=Path("Aidoku-macOS.xcodeproj")
p.mkdir(exist_ok=True)
(p/"project.pbxproj").write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {project};}}\n')
scheme=p/"xcshareddata/xcschemes"
scheme.mkdir(parents=True,exist_ok=True)
ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Aidoku.app" BlueprintName="Aidoku-macOS" ReferencedContainer="container:Aidoku-macOS.xcodeproj"/>'
(scheme/"Aidoku-macOS.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
lock = json.loads(Path("Aidoku.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())
lock.pop("originHash", None)
lock["pins"] = [pin for pin in lock["pins"] if pin["identity"] in {"aidokurunner","wasm3","swiftsoup","swiftlintplugins","zipfoundation"}]
for pin in lock["pins"]:
    if pin["identity"] in {"aidokurunner","zipfoundation"}:
        pin["state"] = {"revision": pin["state"]["revision"]}
lock["version"]=2
dest=p/"project.xcworkspace/xcshareddata/swiftpm"
dest.mkdir(parents=True,exist_ok=True)
(dest/"Package.resolved").write_text(json.dumps(lock,indent=2)+"\n")
