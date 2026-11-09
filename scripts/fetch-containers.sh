#!/bin/bash
# scripts/fetch-containers.sh - Fetch container images via skopeo
# Downloads all required Home Assistant containers for a board

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

register_cleanup

fetch_versions() {
    local channel="$1"
    local arch="$2"
    local machine="$3"

    fetch_version_json "$channel" | jq \
        --arg arch "$arch" \
        --arg machine "$machine" \
        '{
            supervisor: .supervisor,
            homeassistant: .homeassistant[$machine],
            dns: .dns,
            audio: .audio,
            cli: .cli,
            multicast: .multicast,
            observer: .observer,
            images: (.images | to_entries | map(
                # API uses "core" for what we call "homeassistant"
                {key: (if .key == "core" then "homeassistant" else .key end),
                 value: (.value | gsub("\\{arch\\}"; $arch) | gsub("\\{machine\\}"; $machine))}
            ) | from_entries)
        }'
}

fetch_container() {
    local name="$1"
    local version="$2"
    local arch="$3"
    local output_dir="$4"
    local versions_file="$5"

    local image
    image=$(get_container_image "$versions_file" "$name")

    local docker_arch
    docker_arch=$(get_docker_arch "$arch")

    # Check if already downloaded (match by image name prefix)
    local image_prefix="${image//[:\/]/_}"
    if ls "${output_dir}/${image_prefix}"@*.tar &>/dev/null; then
        log "Container already cached: $name"
        return 0
    fi

    log "Fetching Docker image: $image"

    # Get image digest
    local digest
    digest=$(skopeo inspect --override-arch "${docker_arch}" "docker://${image}" | jq -r '.Digest')
    if [ -z "$digest" ] || [ "$digest" = "null" ]; then
        die "Failed to get digest for $image"
    fi

    log "Digest: $digest"

    # Build filename: image_name@digest.tar (replace : and / with _)
    local output_file="${output_dir}/${image_prefix}@${digest//[:\/]/_}.tar"

    # Use skopeo to fetch as docker archive
    skopeo copy \
        --override-arch "${docker_arch}" \
        "docker://${image}" \
        "oci-archive:${output_file}:${image}"

    local size
    size=$(stat -c%s "$output_file")
    log "Downloaded $name: $(bytes_to_human "$size")"
}

main() {
    local board="$1"
    local channel="${2:-$CHANNEL}"

    local arch machine
    arch=$(get_arch "$board")
    machine=$(get_machine "$board")

    log "Fetching containers for board: $board (arch: $arch, machine: $machine)"
    log "Using channel: $channel"

    # Create shared images directory
    local images_dir="${CACHE_DIR}/images"
    mkdir -p "$images_dir"

    # Fetch version information
    if [ -n "$VERSION_FILE" ]; then
        log "Using custom version file: ${VERSION_FILE}"
    else
        log "Fetching version information from ${VERSION_ENDPOINT}/${channel}.json..."
    fi
    local version_json
    version_json=$(fetch_versions "$channel" "$arch" "$machine")

    # Save as board-specific versions file
    echo "$version_json" > "${CACHE_DIR}/versions-${board}.json"
    log "Versions:"
    echo "$version_json" | jq .

    # Fetch each container into shared images directory
    local versions_file="${CACHE_DIR}/versions-${board}.json"
    for container in $CONTAINERS; do
        local version
        version=$(echo "$version_json" | jq -r ".${container}")

        if [ "$version" = "null" ] || [ -z "$version" ]; then
            die "No version found for $container"
        fi

        fetch_container "$container" "$version" "$arch" "$images_dir" "$versions_file"
    done

    log "Container fetch complete"
    log "Total cache size: $(du -sh "$images_dir" | cut -f1)"
}

# Entry point
if [ $# -lt 1 ]; then
    die "Usage: $0 <board> [channel]"
fi

main "$@"
