#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in
  x86_64|amd64) DEB_ARCH=amd64; APPIMAGE_ARCH=x86_64 ;;
  aarch64|arm64) DEB_ARCH=arm64; APPIMAGE_ARCH=aarch64 ;;
  *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

BASE_URL="https://persistent.oaistatic.com/codex-app-prod/linux/deb"
PACKAGES_URL="$BASE_URL/dists/stable/main/binary-${DEB_ARCH}/Packages"

work="${ROOT}/.build"
appdir="$work/AppDir"
rm -rf "$work"
mkdir -p "$appdir"

echo "==> Fetching package index"
curl -fsSL "$PACKAGES_URL" -o "$work/Packages"

version="${VERSION:-$(awk '/^Package: chatgpt$/{f=1} f && /^Version: /{print $2; exit}' "$work/Packages")}"
filename="$(awk -v want="$version" '
  /^Package: chatgpt$/ {pkg=1; ver=""; file=""}
  pkg && /^Version: / {ver=$2}
  pkg && /^Filename: / {file=$2}
  pkg && /^$/ {if (ver==want && file!="") {print file; exit} pkg=0}
  END {if (pkg && ver==want && file!="") print file}
' "$work/Packages" | head -n1)"
sha256="$(awk -v want="$version" '
  /^Package: chatgpt$/ {pkg=1; ver=""; hash=""}
  pkg && /^Version: / {ver=$2}
  pkg && /^SHA256: / {hash=$2}
  pkg && /^$/ {if (ver==want && hash!="") {print hash; exit} pkg=0}
  END {if (pkg && ver==want && hash!="") print hash}
' "$work/Packages" | head -n1)"

if [[ -z "$version" || -z "$filename" || -z "$sha256" ]]; then
  echo "Could not resolve package metadata for chatgpt ${version:-<latest>}" >&2
  exit 1
fi

url="$BASE_URL/$filename"
deb="$work/chatgpt_${version}_${DEB_ARCH}.deb"

echo "==> Downloading ChatGPT Desktop $version ($DEB_ARCH)"
curl -fL "$url" -o "$deb"
echo "$sha256  $deb" | sha256sum -c -

echo "==> Extracting .deb"
dpkg-deb -x "$deb" "$appdir"

# Find desktop file and executable from the package itself.
desktop_src="$(find "$appdir/usr/share/applications" -maxdepth 1 -type f -name '*.desktop' | head -n1 || true)"
if [[ -z "$desktop_src" ]]; then
  echo "No .desktop file found in package" >&2
  exit 1
fi
cp "$desktop_src" "$appdir/$(basename "$desktop_src")"

desktop_name="$(basename "$desktop_src")"
exec_line="$(grep -m1 '^Exec=' "$desktop_src" | cut -d= -f2-)"
exec_cmd="$(printf '%s\n' "$exec_line" | sed -E 's/[[:space:]]+%[A-Za-z]//g' | awk '{print $1}')"
exec_base="$(basename "$exec_cmd")"

# AppImage icon convention: root icon matching Icon= value when possible.
icon_name="$(grep -m1 '^Icon=' "$desktop_src" | cut -d= -f2- || true)"
icon_src=""
if [[ -n "$icon_name" ]]; then
  icon_src="$(find "$appdir/usr/share/icons" "$appdir/usr/share/pixmaps" 2>/dev/null -type f \
    \( -name "$icon_name.png" -o -name "$icon_name.svg" -o -name "$icon_name.xpm" \) | sort | tail -n1 || true)"
fi
if [[ -n "$icon_src" ]]; then
  cp "$icon_src" "$appdir/$(basename "$icon_src")"
fi

cat > "$appdir/AppRun" <<EOF2
#!/usr/bin/env bash
set -e
HERE="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
export PATH="\$HERE/usr/bin:\$PATH"
export LD_LIBRARY_PATH="\$HERE/usr/lib:\$HERE/usr/lib/${DEB_ARCH}-linux-gnu:\${LD_LIBRARY_PATH:-}"

# Prefer the package's own launcher path when present.
if [[ -x "\$HERE${exec_cmd}" ]]; then
  exec "\$HERE${exec_cmd}" "\$@"
fi
if [[ -x "\$HERE/usr/bin/${exec_base}" ]]; then
  exec "\$HERE/usr/bin/${exec_base}" "\$@"
fi

echo "Unable to find packaged executable: ${exec_cmd}" >&2
exit 127
EOF2
chmod +x "$appdir/AppRun"

# Electron/Chromium sandbox often loses suid semantics inside AppImage.
sandbox="$(find "$appdir" -type f -name chrome-sandbox | head -n1 || true)"
if [[ -n "$sandbox" ]]; then
  chmod 4755 "$sandbox" 2>/dev/null || true
fi

APPIMAGETOOL="${APPIMAGETOOL:-$ROOT/appimagetool-${APPIMAGE_ARCH}.AppImage}"
if [[ ! -x "$APPIMAGETOOL" ]]; then
  case "$APPIMAGE_ARCH" in
    x86_64) tool_asset="appimagetool-x86_64.AppImage" ;;
    aarch64) tool_asset="appimagetool-aarch64.AppImage" ;;
  esac
  echo "==> Downloading appimagetool"
  curl -fL "https://github.com/AppImage/appimagetool/releases/download/continuous/$tool_asset" -o "$APPIMAGETOOL"
  chmod +x "$APPIMAGETOOL"
fi

out="${OUT:-$ROOT/ChatGPT-Codex-${version}-${APPIMAGE_ARCH}.AppImage}"
echo "==> Building $out"
ARCH="$APPIMAGE_ARCH" "$APPIMAGETOOL" --appimage-extract-and-run "$appdir" "$out"
chmod +x "$out"

echo
printf 'Built: %s\n' "$out"
printf 'Version: %s\n' "$version"
printf 'Desktop: %s\n' "$desktop_name"
