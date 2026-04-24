# NightsEdge

Custom Firefox build with nightly branding, all telemetry stripped, using a custom `nightsedge` update channel with self-hosted MAR updates. Version string displays as `hydra-<version>` in about:firefox.

## Targets

| Target | Platform | Runner |
|--------|----------|--------|
| `linux-x86_64` | Linux x64 native | `linux/amd64` |
| `linux-aarch64` | Linux ARM cross-compile | `linux/amd64` |

macOS is not currently supported.

## How It Works

1. `FIREFOX_VERSION` pins a specific Firefox hg revision, version, and upstream track
2. On push to `main`, Woodpecker CI builds the configured Linux targets
3. Each build: fetches source at pinned hash, applies mozconfig + prefs + policies, builds, packages, generates MAR
4. Artifacts and MARs are uploaded to the update server

### Version Updates

`scripts/check-and-update-version.sh` supports three upstream tracking modes:

| Track | Upstream Repo | Version Examples | Detection Method |
|-------|----------------|------------------|------------------|
| `release` | `mozilla-release` | `149.0`, `149.0.1` | Latest Firefox release tag |
| `beta` | `mozilla-beta` | `150.0b1`, `150.0b3` | `browser/config/version_display.txt` at tip |
| `nightly` | `mozilla-central` | `151.0a1` | `browser/config/version_display.txt` at tip |

`FIREFOX_VERSION` should contain:

```bash
HG_COMMIT_HASH=<mozilla hg revision>
VERSION=<firefox version string>
UPSTREAM_REPO=<mozilla-release|mozilla-beta|mozilla-central>
FIREFOX_TRACK=<release|beta|nightly>
RUST_VERSION=<stable rustc pin>
```

`RUST_VERSION` must match `MINIMUM_RUST_VERSION` from Firefox's `python/mozboot/mozboot/util.py` at the pinned commit. `build.sh` installs and scopes this exact toolchain via `rustup`/`RUSTUP_TOOLCHAIN`; Mozilla's CI repacks the same stable tarball. Building against rustup's rolling `stable` drifts into breakage on nightly-but-`RUSTC_BOOTSTRAP`-whitelisted crates like `encoding_rs` (portable_simd). `check-and-update-version.sh` derives this field automatically.

For stable release tracking, also include:

```bash
RELEASE_TAG=FIREFOX_149_0_RELEASE
```

Examples:

```bash
# Stable release
HG_COMMIT_HASH=b20f603334b8
VERSION=149.0
UPSTREAM_REPO=mozilla-release
FIREFOX_TRACK=release
RELEASE_TAG=FIREFOX_149_0_RELEASE
RUST_VERSION=1.90.0
```

```bash
# Beta
HG_COMMIT_HASH=<beta hg hash>
VERSION=150.0b3
UPSTREAM_REPO=mozilla-beta
FIREFOX_TRACK=beta
RUST_VERSION=1.90.0
```

```bash
# Nightly
HG_COMMIT_HASH=<central hg hash>
VERSION=151.0a1
UPSTREAM_REPO=mozilla-central
FIREFOX_TRACK=nightly
RUST_VERSION=1.91.0
```

A Windmill cron can run `scripts/check-and-update-version.sh` to refresh `FIREFOX_VERSION` automatically for the configured track, then push the change to Forgejo to trigger CI builds.

## Telemetry Lockdown (3 Layers)

1. **Build flags** — mozconfig disables crashreporter, telemetry reporting, data reporting, health report, Normandy, and signing requirements
2. **Default prefs** — `prefs/nightsedge.js` disables all telemetry pings, studies, experiments, Glean, Pocket, crash reporting, and network services
3. **Enterprise policies** — `policies/policies.json` enforces DisableTelemetry, DisableFirefoxStudies, DisablePocket, and overrides first-run pages

## Local Build

```bash
# Build for Linux x86_64
./scripts/build.sh linux-x86_64

# Cross-compile Linux aarch64 from a Linux x86_64 host
./scripts/build.sh linux-aarch64

```

### Prerequisites

- Mercurial (`hg`)
- Firefox build dependencies (see [Mozilla build docs](https://firefox-source-docs.mozilla.org/setup/linux_build.html))
- Linux builds require a host GCC/libstdc++ development toolchain in addition to Mozilla's downloaded clang toolchain
- Rust toolchain (`rustc`, `cargo`)
- `sccache` if you want compiler caching enabled during builds
- LLVM tools (`llvm-objdump` must be present; on Ubuntu install the `llvm` package)
- A recent LLVM toolchain is required; current Firefox builds need `clang/llvm >= 17`
- CI/local builds should run `./mach bootstrap` to provision Mozilla's expected toolchains instead of relying only on distro package versions
- `linux-aarch64` is configured as a Linux x86_64-hosted cross-compile and relies on Mozilla's `--enable-bootstrap` flow to provision the AArch64 sysroot/toolchain

### `sccache` with MinIO S3

If `sccache` is installed, `scripts/build.sh` enables it automatically for both compiler cache integration and Rust builds. To back the cache with a MinIO bucket, export:

```bash
export AWS_ACCESS_KEY_ID=<minio-access-key>
export AWS_SECRET_ACCESS_KEY=<minio-secret-key>
export SCCACHE_BUCKET=<bucket-name>
export SCCACHE_ENDPOINT=<minio-host:9000>
export SCCACHE_REGION=<region-name>
export SCCACHE_S3_USE_SSL=false
# Optional:
export SCCACHE_S3_KEY_PREFIX=nightsedge/
```

Then run the build normally:

```bash
./scripts/build.sh linux-x86_64
```

Set `SCCACHE_DISABLE=1` to force a build without `sccache`.

### Woodpecker pipeline switches

Set these pipeline environment variables on manual/tag runs when you want to adjust which targets build:

- `BUILD_X86_64=true|false` controls whether the `linux-x86_64` build and package steps run
- `BUILD_AARCH64=true|false` controls whether the `linux-aarch64` build and package steps run

## Update Server

Configure your update server using `update-server/nginx.conf.example` as a starting point. After building:

```bash
# Generate MAR files
./scripts/generate-mar.sh linux-x86_64 https://updates.yourdomain.com

# Generate AUS-compatible update.xml files for all targets
./update-server/generate-update-xml.sh https://updates.yourdomain.com
```

Deploy the `output/update-server/` directory to your web server root.

## Woodpecker CI Secrets

| Secret | Description |
|--------|-------------|
| `FORGEJO_RELEASE_TOKEN` | Forgejo API token used by Woodpecker to upload release artifacts |
| `deploy_key` | SSH private key for artifact upload |
| `deploy_host` | Hostname of the artifact/update server |
| `deploy_user` | SSH user for upload |
| `deploy_path` | Remote path for artifacts |
| `AWS_ACCESS_KEY_ID` | MinIO access key for the `sccache` S3 backend |
| `AWS_SECRET_ACCESS_KEY` | MinIO secret key for the `sccache` S3 backend |
| `SCCACHE_BUCKET` | Bucket used by `sccache` |
| `SCCACHE_ENDPOINT` | MinIO S3 endpoint, for example `minio.internal:9000` |
| `SCCACHE_REGION` | Region value expected by your MinIO deployment |
| `SCCACHE_S3_USE_SSL` | `true` or `false` depending on your MinIO endpoint |
| `SCCACHE_S3_KEY_PREFIX` | Optional object prefix for isolating this cache namespace |

## Repo Structure

```
NightsEdge/
├── FIREFOX_VERSION                # Pinned hg revision + version/track metadata
├── mozconfigs/                    # Build configurations per target
├── policies/policies.json         # Enterprise policies (telemetry lockdown)
├── prefs/nightsedge.js            # Default pref overrides
├── scripts/
│   ├── fetch-source.sh            # Clone the configured upstream repo at pinned hash
│   ├── build.sh                   # Main build orchestrator
│   ├── generate-mar.sh            # Create MAR update files
│   └── check-and-update-version.sh # Windmill cron: detect new release/beta/nightly versions
├── update-server/
│   ├── generate-update-xml.sh     # Generate AUS update XML
│   └── nginx.conf.example         # Example nginx config
└── .woodpecker/                   # CI pipelines
```
