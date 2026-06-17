#!/usr/bin/env bash
#
# install_logic2010.sh — modernized installer for UCLA "Logic 2010".
#
# Usage:
#   ./install_logic2010.sh [options] [path-to-zip]
#
# Options:
#   --app                 Install into ~/Applications as a double-clickable app
#                         (instead of the default ./logic2010 + run script).
#   --prefix DIR          Install directory (default: ./logic2010).
#   --no-verify           Skip the checksum check.
#   -y, --yes             Don't prompt; assume "yes".
#   -h, --help            Show this help.
#
set -euo pipefail

# ---------------------------------------------------------------- config -----
PACKAGE_DEFAULT="InstallLogic2010_mac_20260114.zip"

# Integrity of the distributed zip (computed from the 2026-01-14 package).
EXPECTED_SHA256="b449df0f76ca342058904433a6645a1f688f6951805c8622b0889dcf3952b622"
EXPECTED_MD5="395049d96aa78ba86c406321e5b09a8f"   # fallback only

# If UCLA still hosts the file and you want auto-download when it is missing,
# put the full URL here. Left empty -> install from a local file only.
# NOTE: the URL below is unverified — adjust it if UCLA's path differs.
DOWNLOAD_URL="https://logiclx.humnet.ucla.edu/auto_remote/desktop/20260114/InstallLogic2010_mac_20260114.zip"

# Defaults (overridable by flags).
INSTALL_DIR="./logic2010"
APP_MODE=0
VERIFY=1
ASSUME_YES=0

# --------------------------------------------------------------- helpers -----
err()  { printf '%s\n' "$*" >&2; }
die()  { err "Error: $*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() { sed -n '2,40{/^#/!q;s/^# \{0,1\}//;p}' "$0"; }

confirm() {  # confirm "question" ; returns 0 for yes
    [ "$ASSUME_YES" -eq 1 ] && return 0
    [ -t 0 ] || return 0          # no TTY (piped) -> proceed
    local reply
    printf '%s [Y/n] ' "$1"
    read -r reply || true
    case "${reply:-Y}" in [Nn]*) return 1 ;; *) return 0 ;; esac
}

sha256_of() {  # echoes the sha256 of "$1", or nothing if no tool available
    if   have shasum;     then shasum -a 256 "$1" | awk '{print $1}'
    elif have sha256sum;  then sha256sum     "$1" | awk '{print $1}'
    elif have openssl;    then openssl dgst -sha256 "$1" | awk '{print $NF}'
    fi
}
md5_of() {
    if   have md5sum; then md5sum "$1" | awk '{print $1}'
    elif have md5;    then md5 -q  "$1"
    elif have openssl;then openssl dgst -md5 "$1" | awk '{print $NF}'
    fi
}

# Copy a tree, preserving macOS bundle attributes when possible.
copy_tree() {  # copy_tree SRC DEST_PARENT
    if have ditto; then ditto "$1" "$2/$(basename "$1")"   # native macOS
    else cp -R "$1" "$2/"; fi
}

# Clear the quarantine flag so Gatekeeper won't block this unsigned freeware.
dequarantine() { have xattr && xattr -dr com.apple.quarantine "$1" 2>/dev/null || true; }

# ----------------------------------------------------------- arg parsing -----
PACKAGE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --app)            APP_MODE=1 ;;
        --prefix)         shift; [ $# -gt 0 ] || die "--prefix needs a directory"; INSTALL_DIR="$1" ;;
        --no-verify)      VERIFY=0 ;;
        -y|--yes)         ASSUME_YES=1 ;;
        -h|--help)        usage; exit 0 ;;
        -*)               die "unknown option: $1 (try --help)" ;;
        *)                PACKAGE="$1" ;;
    esac
    shift
done
PACKAGE="${PACKAGE:-$PACKAGE_DEFAULT}"

# --------------------------------------------------------------- licence -----
cat <<'EOF'
This installation script is provided under the terms of the 3-Clause BSD License.
Logic 2010 is provided under a freeware License available on its website.
EOF
confirm "Continue with installation?" || { err "Aborted."; exit 1; }

# --------------------------------------------------- requirements & file -----
have unzip || die "'unzip' is required. Install it with your package manager."

if [ ! -f "$PACKAGE" ]; then
    if [ -n "$DOWNLOAD_URL" ]; then
        have curl || die "'curl' is required to download the package."
        echo "Downloading $PACKAGE ..."
        curl -fL -o "$PACKAGE" "$DOWNLOAD_URL" || die "download failed."
    else
        die "package not found: $PACKAGE
Place the zip next to this script, pass its path as an argument, or set DOWNLOAD_URL."
    fi
fi

# ------------------------------------------------------------- integrity -----
if [ "$VERIFY" -eq 1 ]; then
    got="$(sha256_of "$PACKAGE")"
    if [ -n "$got" ]; then
        [ "$got" = "$EXPECTED_SHA256" ] || die "SHA-256 mismatch!
  expected: $EXPECTED_SHA256
  got:      $got"
        echo "SHA-256 OK."
    else
        got="$(md5_of "$PACKAGE")"
        if [ -n "$got" ]; then
            [ "$got" = "$EXPECTED_MD5" ] || die "MD5 mismatch! (expected $EXPECTED_MD5, got $got)"
            echo "MD5 OK (fallback — no SHA-256 tool found)."
        else
            err "Warning: no checksum tool found; skipping integrity check."
        fi
    fi
else
    err "Warning: integrity check skipped (--no-verify)."
fi

# --------------------------------------------------------------- extract -----
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "Extracting ..."
unzip -q "$PACKAGE" -d "$TMP"

APP_SRC="$(find "$TMP" -maxdepth 2 -type d -name '*.app' | head -1)"
[ -n "$APP_SRC" ] || die "no .app bundle found inside $PACKAGE"
APP_BASENAME="$(basename "$APP_SRC")"

# Sanity-check the bundle is what we expect.
[ -f "$APP_SRC/Contents/Java/logic.jar" ]            || die "logic.jar missing from bundle."
[ -n "$(find "$APP_SRC/Contents/PlugIns" -type f -path '*/bin/java' 2>/dev/null | head -1)" ] \
    || die "bundled Java runtime missing from bundle."

# --------------------------------------------------------------- install -----
if [ "$APP_MODE" -eq 1 ]; then
    DEST="${HOME}/Applications"
    mkdir -p "$DEST"
    rm -rf "$DEST/$APP_BASENAME"
    echo "Installing app to $DEST/$APP_BASENAME ..."
    copy_tree "$APP_SRC" "$DEST"
    dequarantine "$DEST/$APP_BASENAME"
    echo
    echo "Done. Launch it from $DEST/$APP_BASENAME (double-click, or 'open' it)."
else
    mkdir -p "$INSTALL_DIR"
    rm -rf "${INSTALL_DIR:?}/$APP_BASENAME"
    echo "Installing to $INSTALL_DIR/$APP_BASENAME ..."
    copy_tree "$APP_SRC" "$INSTALL_DIR"
    dequarantine "$INSTALL_DIR/$APP_BASENAME"

    # Generate the launcher. The body is written VERBATIM via a QUOTED heredoc
    # ('RUNEOF') so none of its $... is touched by THIS script. That was the bug
    # in the previous version: an *unquoted* heredoc without backslash-escapes
    # expanded $JAVA, $APP, $(uname -s), $(find ...) and "$@" at generation time,
    # producing an empty/garbage launcher (and a stray blank first line, so the
    # shebang wasn't on line 1). With a quoted delimiter the launcher is emitted
    # exactly as written and discovers the .app, the Java runtime and the
    # truststore itself at run time, so it stays self-contained and relocatable.
    RUN="$INSTALL_DIR/runlogic2010.sh"
    cat > "$RUN" <<'RUNEOF'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_DIR="$(find "$HERE" -maxdepth 1 -type d -name '*.app' | head -1)"
[ -n "$APP_DIR" ] || { echo "No .app bundle found next to this script." >&2; exit 1; }
APP="$APP_DIR/Contents"

# Pick a Java runtime: bundled JRE on macOS, system java elsewhere.
JAVA=""
if [ "$(uname -s)" = "Darwin" ]; then
    JAVA="$(find "$APP/PlugIns" -type f -path '*/bin/java' 2>/dev/null | head -1)"
fi
if [ -z "$JAVA" ] || [ ! -x "$JAVA" ]; then
    JAVA="$(command -v java || true)"
fi
if [ -z "$JAVA" ]; then
    echo "No Java runtime found. Install one, e.g.:" >&2
    echo "  Debian/Ubuntu : sudo apt install default-jre" >&2
    echo "  Fedora        : sudo dnf install java-latest-openjdk" >&2
    echo "  Arch          : sudo pacman -S jre-openjdk" >&2
    exit 1
fi

# UCLA pins its server cert: the bundle ships a 1-cert truststore for
# logiclx.humnet.ucla.edu. Without it a system JVM can't validate the server's
# TLS cert ("PKIX path building failed") and the app exits at startup.
TS="$(find "$APP/PlugIns" -type f -name cacerts -path '*/lib/security/*' 2>/dev/null | head -1)"

OPTS=( -Dconfig.dir="$APP/Resources" -Dprog.dir="$APP/Java"
       -Dlink.dir="$APP/Resources" -Droot.dir="$APP" )
[ -n "$TS" ] && OPTS+=( -Djavax.net.ssl.trustStore="$TS"
                        -Djavax.net.ssl.trustStoreType=JKS
                        -Djavax.net.ssl.trustStorePassword=changeit )

exec "$JAVA" "${OPTS[@]}" -cp "$APP/Java/logic.jar" edu.ucla.phil.logic.LogicProgram "$@"
RUNEOF
    chmod +x "$RUN"
    echo
    echo "Installation complete: run '$RUN' to start the program!"
fi

# Platform notes:
#   * Apple Silicon: the bundled JRE is an x86_64 binary, so on M-series Macs it
#     runs through Rosetta 2 (install once: softwareupdate --install-rosetta).
#   * Linux/Windows: the bundled (macOS) JRE can't run there, so the launcher
#     uses your system Java. Any modern JRE works (OpenJDK 8/11/17/21); you just
#     need a graphical desktop session for the window to appear.
#   * Server connection: at startup Logic 2010 contacts logiclx.humnet.ucla.edu
#     over HTTPS using the pinned cert above. That leaf cert expires 2026-12-18;
#     after that you'll need an updated package (or to import the new cert).
