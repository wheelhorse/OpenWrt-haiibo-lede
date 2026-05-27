#!/bin/bash
# Dockerized OpenWrt Build Script
set -e

REPO_URL="https://github.com/coolsnowwolf/lede"
REPO_BRANCH="master"
CONFIG_FILE="configs/x86_64.config"
DIY_SCRIPT="diy-script.sh"
CLASH_KERNEL="amd64"

WORKSPACE_DIR="$PWD"
OPENWRT_PATH="$WORKSPACE_DIR/openwrt"
ARTIFACTS_DIR="$WORKSPACE_DIR/artifacts"

echo "=========================================="
echo " Starting Dockerized OpenWrt Build        "
echo "=========================================="

if [ ! -d "$OPENWRT_PATH" ]; then
    echo "=> Cloning Source Code..."
    git clone $REPO_URL -b $REPO_BRANCH openwrt
else
    echo "=> Source 'openwrt' already exists. Skipping clone."
fi

cd "$OPENWRT_PATH"

# ==========================================
# Clean up state from previous runs
# ==========================================
rm -f "$OPENWRT_PATH/.config"
cp "$WORKSPACE_DIR/$CONFIG_FILE" "$OPENWRT_PATH/.config"

echo "=> Updating and Installing Feeds..."
./scripts/feeds update -a
./scripts/feeds install -a

echo "=> Loading Custom Configuration..."
[ -d "$WORKSPACE_DIR/files" ] && cp -rf "$WORKSPACE_DIR/files" "$OPENWRT_PATH/files"

# Only run DIY script if we haven't already heavily modified the package directory
if [ ! -f "$OPENWRT_PATH/.diy_script_run" ]; then
    chmod +x "$WORKSPACE_DIR/$DIY_SCRIPT"
    "$WORKSPACE_DIR/$DIY_SCRIPT"
    touch "$OPENWRT_PATH/.diy_script_run"
else
    echo "=> DIY Script already run previously. Skipping."
fi

# Preset scripts
[ -f "$WORKSPACE_DIR/scripts/preset-clash-core.sh" ] && "$WORKSPACE_DIR/scripts/preset-clash-core.sh" $CLASH_KERNEL || true
[ -f "$WORKSPACE_DIR/scripts/preset-terminal-tools.sh" ] && "$WORKSPACE_DIR/scripts/preset-terminal-tools.sh" || true
[ -f "$WORKSPACE_DIR/scripts/preset-adguard-core.sh" ] && "$WORKSPACE_DIR/scripts/preset-adguard-core.sh" $CLASH_KERNEL || true

echo "=> Downloading Packages..."
make defconfig
./scripts/feeds install rust || true
make download -j8

# ====================================================================
# HOTFIX: Patch Transmission (Base64 to preserve strict whitespace)
# ====================================================================
echo "=> Applying Transmission miniupnpc compatibility patch..."
mkdir -p feeds/packages/net/transmission/patches/

echo "LS0tIGEvbGlidHJhbnNtaXNzaW9uL3VwbnAuYworKysgYi9saWJ0cmFuc21pc3Npb24vdXBucC5jCkBAIC0xMiw0ICsxMiw1IEBACiAjaW5jbHVkZSA8YXNzZXJ0Lmg+CiAKKyNpbmNsdWRlIDxzdGRkZWYuaD4KICNpbmNsdWRlIDxtaW5pdXBucGMvbWluaXVwbnBjLmg+CiAjaW5jbHVkZSA8bWluaXVwbnBjL3VwbnBjb21tYW5kcy5oPgpAQCAtMjE5LDQgKzIyMCw3IEBACiAgICAgaWYgKGRldmxpc3QpCiAgICAgewogICAgICAgICBGcmVlVVBOUFVybHMgKCZoYW5kbGUtPnVybHMpOwotICAgICAgICBpZiAoVVBOUF9HZXRWYWxpZElHRCAoZGV2bGlzdCwgJmhhbmRsZS0+dXJscywgJmhhbmRsZS0+ZGF0YSwKLSAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGhhbmRsZS0+bGFuYWRkciwgc2l6ZW9mIChoYW5kbGUtPmxhbmFkZHIpKSA9PSAxKQorICAgICAgICBpZiAoVVBOUF9HZXRWYWxpZElHRCAoZGV2bGlzdCwgJmhhbmRsZS0+dXJscywgJmhhbmRsZS0+ZGF0YSwgaGFuZGxlLT5sYW5hZGRyLCBzaXplb2YgKGhhbmRsZS0+bGFuYWRkcikKKyNpZiBNSU5JVVBOUENfQVBJX1ZFUlNJT04gPj0gMTgKKyAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICwgTlVMTCwgMAorI2VuZGlmCisgICAgICAgICAgICAgICAgICAgICAgICAgICAgICApID09IDEpCiAgICAgICAgIHsKICAgICAgICAgICAgIHRyX2xvZ0FkZEluZm8gKF8oIkZvdW5kIEludGVybmV0IEdhdGV3YXkgRGV2aWNlIFwiJXNcIiIpLA==" | base64 -d > feeds/packages/net/transmission/patches/0004-fix-miniupnpc-2.3-compat.patch
# ====================================================================

echo "=> Compiling Firmware with $(nproc) threads..."
mkdir -p files/etc/uci-defaults
[ -f "$WORKSPACE_DIR/scripts/init-settings.sh" ] && cp "$WORKSPACE_DIR/scripts/init-settings.sh" files/etc/uci-defaults/99-init-settings

# Attempt multi-thread, fallback to single-thread with verbose logging on failure
set +e
make -j$(nproc) V=sc || make -j1 || make -j1 V=s
BUILD_STATUS=$?
set -e

if [ $BUILD_STATUS -ne 0 ]; then
    echo "❌ Compilation failed."
    exit 1
fi

echo "=> Organizing Artifacts..."
mkdir -p "$ARTIFACTS_DIR"
cp -r "$OPENWRT_PATH/bin/targets/"* "$ARTIFACTS_DIR/"
cp "$OPENWRT_PATH/.config" "$ARTIFACTS_DIR/build.config"

echo "✅ Build Complete! Firmware saved to ./artifacts"
