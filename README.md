# NightsEdge

NightsEdge is a privacy-focused desktop Firefox build based on a pinned upstream Firefox revision. It keeps Firefox Nightly branding, uses the display name **Firefox Nightly (NightsEdge)** and version string `hydra-<version>`, and is configured for a custom `nightsedge` update channel with self-hosted MAR updates.

Telemetry, data reporting, crash reporting, studies, Pocket, sponsored content, and recommendation services are disabled through build flags, default preferences, and enterprise policies. The telemetry `pingsender` is not built or packaged.

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

## Configuration

| Path | Purpose |
| --- | --- |
| `FIREFOX_VERSION` | Pins the upstream revision, Firefox version and track, release tag, and compatible Rust version. |
| `mozconfigs/common.mozconfig` | Shared branding, update-channel, privacy, optimization, and cache settings. |
| `mozconfigs/<target>.mozconfig` | Target triple and platform-specific cross-compilation settings. |
| `prefs/nightsedge.js` | Default privacy, UI, theme, and update preferences. |
| `policies/policies.json` | Locked enterprise policies applied to new and existing profiles. |
| `.woodpecker/build.yml` | CI targets, cache backend, update URL, artifact uploads, and releases. |
| `.woodpecker/website.yml` | Builds and publishes the homepage/update-server container. |
| `website/` | Static homepage, nginx routing, and container definition. |

`FIREFOX_TRACK` supports `release` from `mozilla-release`, `beta` from `mozilla-beta`, or `nightly` from `mozilla-central`. Run `./scripts/check-and-update-version.sh` to check the configured track; add `--write`, `--commit`, or `--push` to apply and publish an update. The script also refreshes the Rust pin.

Stable release example:

```bash
HG_COMMIT_HASH=931e624c6f53269d41e57ecefca418ef7fdb0f75
VERSION=152.0
UPSTREAM_REPO=mozilla-release
FIREFOX_TRACK=release
RELEASE_TAG=FIREFOX_152_0_RELEASE
RUST_VERSION=1.90.0
```

Beta example:

```bash
HG_COMMIT_HASH=<beta hg revision>
VERSION=153.0b3
UPSTREAM_REPO=mozilla-beta
FIREFOX_TRACK=beta
RUST_VERSION=<tested rust version>
```

Nightly example:

```bash
HG_COMMIT_HASH=<central hg revision>
VERSION=154.0a1
UPSTREAM_REPO=mozilla-central
FIREFOX_TRACK=nightly
RUST_VERSION=<tested rust version>
```

## Building

Builds run on Linux x86_64. All targets except Linux x86_64 are cross-compiled.

| Target | Platform | CI gate |
| --- | --- | --- |
| `linux-x86_64` | Linux x64, native | `BUILD_X86_64` |
| `linux-aarch64` | Linux ARM64, cross-compiled | `BUILD_AARCH64` |
| `windows-x86_64` | Windows x64, clang-cl cross-compile | `BUILD_WINDOWS_X86_64` |
| `macos-x86_64` | macOS Intel, cross-compiled | `BUILD_MACOS_X86_64` |
| `macos-aarch64` | macOS Apple Silicon, cross-compiled | `BUILD_MACOS_AARCH64` |

Install the [Firefox build prerequisites](https://firefox-source-docs.mozilla.org/setup/linux_build.html), `git`, `curl`, Python 3, `rustup`, a GCC/libstdc++ development toolchain, and recent LLVM tools (`clang`/`llvm` 17 or newer, including `llvm-objdump`). Windows cross-builds also require `msitools` and `libc6-i386`. `sccache` is optional.

Run:

```bash
./scripts/build.sh <target>
```

The script fetches the Firefox revision pinned in `FIREFOX_VERSION`, applies the patches and configuration, runs Mozilla's toolchain bootstrap, then builds and packages the browser. Artifacts are written under `mozilla-release/obj-*/dist/`.

If `sccache` is installed, it is enabled automatically for C/C++ and Rust. Set `SCCACHE_DISABLE=1` to disable it. An S3-compatible cache can be configured with `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `SCCACHE_BUCKET`, `SCCACHE_ENDPOINT`, `SCCACHE_REGION`, and `SCCACHE_S3_USE_SSL`.

Important build notes:

- The checkout at `mozilla-release/` is forcibly restored to the pinned revision on each build; do not keep source changes there.
- macOS builds are ad-hoc signed but not Apple-signed or notarized. First launch may require right-clicking **Open** or running `xattr -cr NightsEdge.app`.

## Self-hosted updates

After building a target, generate its complete MAR and AUS-compatible `update.xml` with:

```bash
./scripts/generate-mar.sh <target> https://nightsedge.hydranet.dev
```

The files are written to `output/mar/<target>/`. Host the MAR at `https://nightsedge.hydranet.dev/mar/<target>/` and publish each generated XML file at the matching `https://nightsedge.hydranet.dev/updates/%BUILD_TARGET%.xml` path.

## CI

Woodpecker runs on pushes to `main`, manual runs, and tags using a Linux x86_64 runner. It fetches the pinned source, runs separate build and package steps for each enabled target, generates complete MAR files and update XML, then stages the results under `artifacts/`. All five target gates are enabled by default in `.woodpecker/build.yml`.

Builds use `sccache` with the configured MinIO S3 backend. Every pipeline uploads a zipped artifact mirror to MinIO; tag pipelines also publish the platform packages and update files to a Forgejo release. CI reads the cache credentials from the `CACHE_S3_ACCESS_KEY` and `CACHE_S3_SECRET_KEY` Woodpecker secrets. Tagged Forgejo releases also require `FORGEJO_RELEASE_TOKEN`.

The website workflow publishes a static nginx image to `registry.hydranet.dev` after website changes and on manual runs. Configure these Woodpecker repository secrets:

- `WEBSITE_CONTAINER_IMAGE`: full repository name, for example `registry.hydranet.dev/nightsedge/website`
- `CONTAINER_REGISTRY_USERNAME`
- `CONTAINER_REGISTRY_PASSWORD`

The Woodpecker agent must allow `woodpeckerci/plugin-docker-buildx:6.1.1` as a privileged plugin. The container listens on port `8080`; nginx serves the homepage and proxies `/releases/`, `/mar/`, and `/updates/` to the public-read `nightsedge-releases` MinIO bucket.

The optional Windmill job in `.windmill/auto_update.py` checks for upstream updates, commits and pushes new pins, waits for the push build, and creates a release tag only after that build succeeds. The tag starts the release pipeline.
