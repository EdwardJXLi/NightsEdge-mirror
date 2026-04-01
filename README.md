# NightsEdge

Custom Firefox build: stable release code with nightly branding, all telemetry stripped, using a custom `nightsedge` update channel with self-hosted MAR updates. Version string displays as `hydra-<version>` in about:firefox.

## Targets

| Target | Platform | Runner |
|--------|----------|--------|
| `linux-x86_64` | Linux x64 native | `linux/amd64` |
| `linux-aarch64` | Linux ARM cross-compile | `linux/amd64` |
| `win-x86_64` | Windows x64 cross-compile | `linux/amd64` |

macOS is not currently supported.

## How It Works

1. `FIREFOX_VERSION` pins a specific mozilla-release commit hash
2. On push to `main`, Woodpecker CI builds all three targets
3. Each build: fetches source at pinned hash, applies mozconfig + prefs + policies, builds, packages, generates MAR
4. Artifacts and MARs are uploaded to the update server

### Version Updates

A Windmill daily cron runs `scripts/check-and-update-version.sh` which checks mozilla-release for new stable tags. If a new version is found, it updates `FIREFOX_VERSION` and pushes to Forgejo, triggering CI builds automatically.

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

# Build for Windows (cross-compile, requires mingw-w64 + wine)
./scripts/build.sh win-x86_64
```

### Prerequisites

- Mercurial (`hg`)
- Firefox build dependencies (see [Mozilla build docs](https://firefox-source-docs.mozilla.org/setup/linux_build.html))
- Rust toolchain (`rustc`, `cargo`)
- LLVM tools (`llvm-objdump` must be present; on Ubuntu install the `llvm` package)
- A recent LLVM toolchain is required; current Firefox builds need `clang/llvm >= 17`
- CI/local builds should run `./mach bootstrap` to provision Mozilla's expected toolchains instead of relying only on distro package versions
- `linux-aarch64` is configured as a Linux x86_64-hosted cross-compile and relies on Mozilla's `--enable-bootstrap` flow to provision the AArch64 sysroot/toolchain
- For Windows cross-compile: `mingw-w64`, `wine64`

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
| `update_url_base` | Base URL for update server (e.g., `https://updates.yourdomain.com`) |
| `deploy_key` | SSH private key for artifact upload |
| `deploy_host` | Hostname of the artifact/update server |
| `deploy_user` | SSH user for upload |
| `deploy_path` | Remote path for artifacts |

## Repo Structure

```
NightsEdge/
├── FIREFOX_VERSION                # Pinned hg commit hash + version metadata
├── mozconfigs/                    # Build configurations per target
├── policies/policies.json         # Enterprise policies (telemetry lockdown)
├── prefs/nightsedge.js            # Default pref overrides
├── scripts/
│   ├── fetch-source.sh            # Clone mozilla-release at pinned hash
│   ├── build.sh                   # Main build orchestrator
│   ├── generate-mar.sh            # Create MAR update files
│   └── check-and-update-version.sh # Windmill cron: detect new releases
├── update-server/
│   ├── generate-update-xml.sh     # Generate AUS update XML
│   └── nginx.conf.example         # Example nginx config
└── .woodpecker/                   # CI pipelines (3 targets)
```
