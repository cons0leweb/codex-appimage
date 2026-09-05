# ChatGPT / Codex Desktop AppImage

Unofficial AppImage repackaging helper for OpenAI's official Linux ChatGPT desktop `.deb`.

It does **not** rebuild or patch the desktop app. It downloads OpenAI's package metadata, downloads the official `.deb`, verifies its SHA-256 from the package index, extracts it, and wraps the extracted files as an AppImage.

## Build

Requirements:

- `bash`
- `curl`
- `dpkg-deb`
- `sha256sum`
- FUSE support is not required during build because appimagetool is invoked with `--appimage-extract-and-run`.

```bash
./build.sh
```

To pin a specific OpenAI package version:

```bash
VERSION=26.810.41047 ./build.sh
```

Output:

```text
ChatGPT-Codex-<version>-x86_64.AppImage
```

Run it:

```bash
chmod +x ChatGPT-Codex-*.AppImage
./ChatGPT-Codex-*.AppImage
```

If Chromium sandboxing causes a launch failure on a particular distro, test whether the upstream package itself launches there first. Avoid permanently adding `--no-sandbox` unless you deliberately accept the security tradeoff.

## CI

`.github/workflows/build.yml` builds x86_64 on pushes, daily, and manually. Manual runs additionally update a prerelease tag named `appimage-latest`.

## Notes

OpenAI currently publishes official Linux `.deb` / `.rpm` builds. The package index provides versioned package paths and SHA-256 hashes, so this script uses that rather than trusting the mutable `latest/` URL.
