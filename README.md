# HAOS Full Images

This repository contains a builder for Home Assistant OS images with preloaded
images of the latest Home Assistant components. This allows for offline
installation of Home Assistant OS with the latest versions and minimal wait
on the first boot.

## Usage

```bash
# Build the builder container
make docker-image

# Build a single image
make build IMAGE=haos_green-17.0.img.xz

# Build all images in input/
make build-all

# Use beta channel
make build IMAGE=haos_green-17.0.img.xz CHANNEL=beta

# Pre-fetch containers
make fetch BOARD=green

# Interactive shell for debugging
make shell
```

## Make Targets

| Target | Description |
|--------|-------------|
| `docker-image` | Build the builder container |
| `build IMAGE=<file>` | Build single full image |
| `build-all` | Build all images in `input/` |
| `fetch BOARD=<name>` | Download containers only |
| `clean` | Clean work directory |
| `shell` | Interactive shell in container |

## Directories

| Path | Description |
|------|-------------|
| `cache/` | Container image cache |
| `input/` | Place HAOS images here |
| `output/` | Built images appear here |


## Embedded Containers

Latest supervisor, homeassistant, dns, audio, cli, multicast, observer

Versions fetched from `version.home-assistant.io` based on `CHANNEL` (default: `stable`).

## Releases

Run the `Build single channel images` workflow with:

- `channel`: `stable`, `beta`, or `dev`.
- `version_sha`: commit in `home-assistant/version` (required for publishing).
- `publish`: create a release; defaults to artifacts only. Requires `main` and
  `stable` or `beta`. Beta releases are marked as prereleases.
- `force`: bypass unchanged-input detection after a builder fix. To reuse a
  version SHA, delete its release and tag first with
  `gh release delete <tag> --cleanup-tag`. Published releases are never overwritten.

Image filenames: `haos_<board>-<os>-full-core-<core>-<channel>-<revision>.<format>`.

### Verify downloads

Download the image, `SHA256SUMS`, and `SHA256SUMS.sigstore.json` from the same release:

```bash
cosign verify-blob SHA256SUMS \
  --bundle SHA256SUMS.sigstore.json \
  --certificate-identity 'https://github.com/home-assistant/operating-system-full-images/.github/workflows/build-channel.yml@refs/heads/main' \
  --certificate-github-workflow-repository 'home-assistant/operating-system-full-images' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com'
sha256sum --check --ignore-missing SHA256SUMS
```
