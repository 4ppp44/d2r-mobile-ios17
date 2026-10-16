#!/bin/bash
# Source-only build. Requires assets generated locally from your own game files.
# Does not install, launch, sign or export an IPA.
set -euo pipefail
cd "$(dirname "$0")"
: "${DM_ROOT:?Set DM_ROOT to your private generated work directory}"
: "${DM_OUT:?Set DM_OUT to your verified r44-touch output directory}"
: "${DM_ASTC_PACK:?Set DM_ASTC_PACK to your complete locally generated ASTC pack}"
: "${DM_BUNDLE_ID:?Set your own DM_BUNDLE_ID}"
export DM_TEAM_ID="${DM_TEAM_ID:-}"
export DM_BUILD_NUMBER="${DM_BUILD_NUMBER:-1}"
export DM_DEVICE_FAMILY="${DM_DEVICE_FAMILY:-1}"
export DM_FREE_ACCOUNT=1 DM_GEN_ONLY=1
# Direct-install PNG icons use CFBundleIcons; no simulator download required.
# Catalog mode is for an SDK-matched simulator environment, not just any iOS runtime.
ICON_MODE=${DM_IOS17_ICON_MODE:-png}
case "$ICON_MODE" in png|catalog) ;; *) echo "Invalid DM_IOS17_ICON_MODE (png or catalog)" >&2; exit 64 ;; esac
# Verify the actual translator/toolchain before expensive asset generation.
python3 ../gfx/tools/dmsh_chain.py --check-tools
# run.sh's build branch only generates assets/project with DM_GEN_ONLY=1.
bash ./run.sh build
if [ "$ICON_MODE" = png ]; then
 python3 tools/project_free.py project.yml project_icons_free.yml
 python3 tools/ios17_png_icons.py project_icons_free.yml project_icons.yml Assets.xcassets/AppIcon.appiconset/AppIcon1024.png Gen/AppIcons
 xcodegen generate -q --spec project_icons.yml
 python3 -c 'from pathlib import Path; [Path(p).unlink() for p in ("project_icons_free.yml", "project_icons.yml")]'
fi
xcodebuild -project DmIOS.xcodeproj -target DmIOS -configuration Release \
 -sdk iphoneos -arch arm64 \
 SYMROOT="${DM_IOS_DD:-$DM_ROOT/build/ios17-source}/Build/Products" \
 OBJROOT="${DM_IOS_DD:-$DM_ROOT/build/ios17-source}/Build/Intermediates.noindex" \
 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
 IPHONEOS_DEPLOYMENT_TARGET=17.0 TARGETED_DEVICE_FAMILY="$DM_DEVICE_FAMILY" \
 OTHER_CFLAGS='$(inherited) -mcpu=apple-a16 -DDM_NVN_M3=1 -DDM_LEGACY_IOS17=1' \
 GCC_PREPROCESSOR_DEFINITIONS='$(inherited) DM_NVN_M3=1 DM_LEGACY_IOS17=1' \
 CURRENT_PROJECT_VERSION="$DM_BUILD_NUMBER" build
