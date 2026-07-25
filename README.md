# NightsEdge

NightsEdge is a privacy-focused desktop Firefox build maintained by
[RadioactiveHydra / EdwardJXLi](https://github.com/EdwardJXLi). It follows a
pinned upstream Firefox revision and stays close to upstream while applying a
small set of branding, privacy, and interface changes.

[Homepage](https://nightsedge.hydranet.dev/) ·
[Downloads](https://nightsedge.hydranet.dev/#downloads) ·
[Firefox source documentation](https://firefox-source-docs.mozilla.org/)

## Overview

- Uses Firefox Nightly branding with the display name **Firefox Nightly
  (NightsEdge)** and the version string `hydra-<version>`.
- Disables telemetry, data and crash reporting, studies, Pocket, sponsored
  content, and recommendation services through build flags, default
  preferences, and enterprise policies.
- Does not build or package Firefox's standalone telemetry `pingsender`.
- Uses the custom `nightsedge` update channel with self-hosted, signed MAR
  updates.
- Builds packages for Linux, Windows, and macOS from a Linux x86_64 host.

## Building

Install the
[Firefox build prerequisites](https://firefox-source-docs.mozilla.org/setup/linux_build.html)
along with:

- `git`, `curl`, Python 3, and `rustup`
- A GCC/libstdc++ development toolchain
- LLVM 17 or newer, including `clang` and `llvm-objdump`
- `msitools` and `libc6-i386` for Windows cross-builds
- `sccache` (optional)

Then run:

```bash
./scripts/build.sh <target>
```

Available targets:

| Target | Platform | Build type | CI gate |
| --- | --- | --- | --- |
| `linux-x86_64` | Linux x64 | Native | `BUILD_X86_64` |
| `linux-aarch64` | Linux ARM64 | Cross-compiled | `BUILD_AARCH64` |
| `windows-x86_64` | Windows x64 | Cross-compiled with clang-cl | `BUILD_WINDOWS_X86_64` |
| `macos-x86_64` | macOS Intel | Cross-compiled | `BUILD_MACOS_X86_64` |
| `macos-aarch64` | macOS Apple Silicon | Cross-compiled | `BUILD_MACOS_AARCH64` |

The build script fetches the revision pinned in `FIREFOX_VERSION`, applies the
project's patches and configuration, runs Mozilla's toolchain bootstrap, and
packages the browser. Artifacts are written under
`mozilla-release/obj-*/dist/`.

> **Build notes**
>
> - The checkout at `mozilla-release/` is forcibly restored to the pinned
>   revision on every build. Do not keep source changes there.
> - macOS builds are ad-hoc signed, but are not signed with an Apple Developer
>   ID or notarized. First launch may require right-clicking **Open** or running
>   `xattr -cr NightsEdge.app`.

### Compiler cache

If `sccache` is installed, it is enabled automatically for C/C++ and Rust. Set
`SCCACHE_DISABLE=1` to disable it.

To use an S3-compatible cache, configure `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`, `SCCACHE_BUCKET`, `SCCACHE_ENDPOINT`,
`SCCACHE_REGION`, and `SCCACHE_S3_USE_SSL`.

## Version pinning

`FIREFOX_VERSION` is the source of truth for the upstream revision, Firefox
version and track, release tag, and compatible Rust version.

| Track | Upstream repository | Version example | Release tag |
| --- | --- | --- | --- |
| `release` | `mozilla-release` | `152.0.6` | Required |
| `beta` | `mozilla-beta` | `153.0b3` | Omitted |
| `nightly` | `mozilla-central` | `154.0a1` | Omitted |

Check the configured track for a newer Firefox version:

```bash
./scripts/check-and-update-version.sh
```

Add `--write` to update `FIREFOX_VERSION`, `--commit` to commit the update, or
`--push` to commit and push it. The script also refreshes the compatible Rust
pin.

## Configuration

| Path | Purpose |
| --- | --- |
| `FIREFOX_VERSION` | Pinned upstream revision, Firefox version and track, release tag, and Rust version. |
| `mozconfigs/common.mozconfig` | Shared branding, update-channel, privacy, optimization, and cache settings. |
| `mozconfigs/<target>.mozconfig` | Target triple and platform-specific cross-compilation settings. |
| `prefs/nightsedge.js` | Default privacy, UI, theme, and update preferences. |
| `policies/policies.json` | Locked enterprise policies applied to new and existing profiles. |
| `.woodpecker/build.yml` | CI targets, cache backend, update URL, artifact uploads, releases, and site publishing. |
| `website/` | Static homepage, nginx routing, and container definition. |

## Patches

Every patch in `patches/` is applied automatically during a build.

| Patch | Change |
| --- | --- |
| `about-dialog-branding.patch` | Identifies the browser as NightsEdge and links to the maintainer in the About dialog. |
| `branding-displayname.patch` | Sets the desktop display name and a distinct macOS bundle name. |
| `configurable-theme-background-sidebar.patch` | Keeps theme backgrounds in the top toolbox by default; set `browser.theme.background-image-on-sidebar.enabled` to `true` for a continuous vertical-tabs sidebar background. |
| `default-browser-message.patch` | Replaces the default-browser confirmation text. |
| `macos-about-in-help.patch` | Keeps About available in the macOS Help menu. |
| `package-default-preferences.patch` | Loads `prefs/nightsedge.js` after Firefox's defaults. |
| `package-enterprise-policies.patch` | Includes `policies/policies.json` in non-Mozilla builds. |
| `remove-pingsender.patch` | Removes the standalone telemetry pingsender. |

## Self-hosted updates

After building a target, generate its complete MAR and AUS-compatible
`update.xml`:

```bash
./scripts/generate-mar.sh <target> https://nightsedge.hydranet.dev
```

Generated files are written to `output/mar/<target>/`. Signed MARs are
published under
`https://nightsedge.hydranet.dev/mar/<build-id>/<target>/`, while the matching
update XML files are baked into the website image at
`https://nightsedge.hydranet.dev/updates/%BUILD_TARGET%.xml`. Versioned
packages and homepage download links use
`https://nightsedge.hydranet.dev/releases/<version>/`.

---

NightsEdge is independent from Mozilla. Firefox and the Firefox logos are
trademarks of the Mozilla Foundation.
