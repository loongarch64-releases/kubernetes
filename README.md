# kubenetes (LoongArch64 Build)

[![Build Status](https://github.com/loongarch64-releases/kubenetes/actions/workflows/release.yml/badge.svg)](https://github.com/loongarch64-releases/kubenetes/actions)

This repository contains the LoongArch64 build configuration and scripts for **[kubenetes](https://github.com/kubenetes/kubenetes)**, originally developed by **kubenetes**.

## Quick Start

### Prerequisites
- A LoongArch64 environment (native or QEMU user emulation).
- Docker (optional, for containerized builds).

### Build from Source

1. **Clone this repository**:
   ```bash
   git clone https://github.com/loongarch64-releases/kubenetes.git
   cd kubenetes
   ```

2. **Get latest version
   ```bash
   ./scripts/get_version.sh
   x.y.z
   ```

3. **Run the build script**:
   ```bash
   ./scripts/build.sh x.y.z
   ```
   *Or build inside a Docker container:*
   ```bash
   ./scripts/build_in_docker.sh x.y.z
   ```

4. **Get the binary**:
   The compiled binaries will be available in the `dists/x.y.z` directory.

## Development

- **Source Code**: The original source is managed upstream at [kubenetes/kubenetes](https://github.com/kubenetes/kubenetes).
- **Patches**: Any LoongArch-specific patches are stored in the `patches/` directory (if applicable).
- **CI/CD**: Automated builds are handled via GitHub Actions (see `.github/workflows/`).

## License

This build wrapper inherits the license of the original project: **kubenetes/kubenetes**.

Please refer to the upstream repository for the full license text.

---
*Generated automatically from release-tools.*
