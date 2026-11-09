#!/bin/bash
# scripts/lib.sh - Shared functions for HAOS Full Image Builder

# Only enable strict mode when running as main script (not when sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
fi

# Configurable variables with defaults
VERSION_ENDPOINT="${VERSION_ENDPOINT:-https://version.home-assistant.io}"
VERSION_FILE="${VERSION_FILE:-}"
CHANNEL="${CHANNEL:-stable}"
CONTAINERS="${CONTAINERS:-supervisor homeassistant dns audio cli multicast observer}"
WORK_DIR="${WORK_DIR:-/work}"
INPUT_DIR="${INPUT_DIR:-/input}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
CACHE_DIR="${CACHE_DIR:-/cache}"
XZ_COMPRESSION_LEVEL="${XZ_COMPRESSION_LEVEL:-3}"
XZ_THREADS="${XZ_THREADS:-0}"
SECTOR_SIZE="${SECTOR_SIZE:-512}"
DIND_IMAGE="${DIND_IMAGE:-docker:dind}"

#
# Path helpers (evaluated at call time)
#

get_new_data_image_path() {
    echo "${WORK_DIR}/hassos-data-new.img"
}

get_data_content_path() {
    echo "${WORK_DIR}/data"
}

get_disk_image_path() {
    echo "${WORK_DIR}/disk.img"
}

get_partition_image_path() {
    local label="$1"
    echo "${WORK_DIR}/${label}.img"
}

get_spl_image_path() {
    echo "${WORK_DIR}/spl.img"
}

get_partition_table_json_path() {
    echo "${WORK_DIR}/partition_table.json"
}

get_original_directory_path() {
    echo "${WORK_DIR}/original"
}

get_original_data_path() {
    echo "${WORK_DIR}/original/data"
}

get_original_settings_path() {
    echo "${WORK_DIR}/original/settings"
}

#
# Logging functions
#

# Color codes (enabled if terminal or LOG_COLOR=1, disabled if LOG_COLOR=0)
if [[ "${LOG_COLOR:-}" == "1" ]] || { [[ "${LOG_COLOR:-}" != "0" ]] && [[ -t 2 ]]; }; then
    _LOG_RESET='\033[0m'
    _LOG_RED='\033[0;31m'
    _LOG_YELLOW='\033[0;33m'
    _LOG_CYAN='\033[0;36m'
    _LOG_DIM='\033[0;90m'
else
    _LOG_RESET=''
    _LOG_RED=''
    _LOG_YELLOW=''
    _LOG_CYAN=''
    _LOG_DIM=''
fi

log() {
    echo -e "${_LOG_DIM}[$(date '+%H:%M:%S')]${_LOG_RESET} $*" >&2
}

die() {
    echo -e "${_LOG_DIM}[$(date '+%H:%M:%S')]${_LOG_RESET} ${_LOG_RED}ERROR:${_LOG_RESET} $*" >&2
    exit 1
}

#
# Cleanup and trap handling
#

# Global array to track mounted filesystems
declare -a MOUNTED_PATHS=()

cleanup() {
    local exit_code=$?
    log "Cleaning up..."

    # Unmount any mounted filesystems
    for mount_path in "${MOUNTED_PATHS[@]:-}"; do
        if mountpoint -q "$mount_path" 2>/dev/null; then
            log "Unmounting $mount_path"
            umount "$mount_path" || true
        fi
    done

    exit $exit_code
}

# Register cleanup trap
register_cleanup() {
    trap cleanup EXIT ERR INT TERM
}

# Track a mount point for cleanup
track_mount() {
    local mount_path="$1"
    MOUNTED_PATHS+=("$mount_path")
}

#
# Prerequisite checks
#

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "This script must be run as root"
}

require_file() {
    [ -f "$1" ] || die "Required file not found: $1"
}

require_directory() {
    [ -d "$1" ] || die "Required directory not found: $1"
}

#
# Loop device helpers
#

ensure_loop_devices() {
    # Create loop device nodes if they don't exist
    for i in $(seq 0 15); do
        if [ ! -e "/dev/loop$i" ]; then
            mknod "/dev/loop$i" b 7 "$i" 2>/dev/null || true
        fi
    done
}

# Setup loop device for an image file
# Returns the loop device path
setup_loop() {
    local image="$1"

    ensure_loop_devices

    local flags="--find --show"

    losetup $flags "$image"
}

# Detach a loop device
detach_loop() {
    local loop_dev="$1"
    losetup -d "$loop_dev" 2>/dev/null || true
}

#
# Architecture and machine mappings
#

get_arch() {
    local board="$1"
    case "$board" in
        generic-x86-64|ova)
            echo "amd64"
            ;;
        *)
            echo "aarch64"
            ;;
    esac
}

# Convert HAOS architecture names to Docker/OCI/Go architecture names
get_docker_arch() {
    local arch="$1"
    case "$arch" in
        aarch64)
            echo "arm64"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

get_machine() {
    local board="$1"
    case "$board" in
        generic-aarch64)
            echo "qemuarm-64"
            ;;
        odroid-m1s)
            echo "odroid-m1"
            ;;
        ova)
            echo "qemux86-64"
            ;;
        rpi3-64)
            echo "raspberrypi3-64"
            ;;
        rpi4-64)
            echo "raspberrypi4-64"
            ;;
        rpi5-64)
            echo "raspberrypi5-64"
            ;;
        *)
            echo "$board"
            ;;
    esac
}

# Check if board is a VM type requiring special output formats
is_vm_board() {
    local board="$1"
    case "$board" in
        ova|generic-aarch64)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Get SPL (Secondary Program Loader) size in bytes for a board, 0 if none
get_spl_size() {
    local board="$1"
    case "$board" in
        khadas-vim3|odroid-c2|odroid-c4|odroid-n2)
            echo "8388608"   # 8M
            ;;
        green|odroid-m1|odroid-m1s)
            echo "16777216"  # 16M
            ;;
        *)
            echo "0"
            ;;
    esac
}

# MBR partition index to label (0-based, matching sfdisk JSON order)
get_mbr_partition_label() {
    local index="$1"
    case "$index" in
        0) echo "hassos-boot" ;;
        # 1 is the extended partition container
        2) echo "hassos-overlay" ;;
        3) echo "hassos-data" ;;
        4) echo "hassos-kernel0" ;;
        5) echo "hassos-system0" ;;
        6) echo "hassos-kernel1" ;;
        7) echo "hassos-system1" ;;
        8) echo "hassos-bootstate" ;;
        *) ;;
    esac
}

get_partition_table_type() {
    local board="$1"
    case "$board" in
        generic-aarch64|generic-x86-64|ova|rpi5-64)
            echo "gpt"
            ;;
        green|rpi3-64|rpi4-64|odroid-m1|odroid-m1s|yellow)
            echo "hybrid"
            ;;
        khadas-vim3|odroid-c2|odroid-c4|odroid-n2)
            echo "mbr"
            ;;
        *)
            die "Unknown partition table type for board: $board"
            ;;
    esac
}

#
# Board detection from filename
#

# Extract board from HAOS image filename
# e.g., haos_green-17.0.rc2.img.xz -> green
get_board_from_filename() {
    local filename="$1"
    local basename
    basename=$(basename "$filename")

    # Remove haos_ prefix and version suffix
    # Pattern: haos_<board>-<version>.<ext>
    local board
    board=$(echo "$basename" | sed -E 's/^haos_//; s/-[0-9]+\.[0-9]+.*$//')

    echo "$board"
}

# Extract version from HAOS image filename
# e.g., haos_green-17.0.rc2.img.xz -> 17.0.rc2
get_version_from_filename() {
    local filename="$1"
    local basename
    basename=$(basename "$filename")

    # Extract version - it's the part after the last hyphen before extension
    # that starts with a digit
    # Pattern: haos_<board>-<version>.(img|qcow2).xz
    local version
    # Remove extension first, then extract version (number.number...)
    version=$(echo "$basename" | sed -E 's/\.(img|qcow2)\.xz$//' | grep -oE '[0-9]+\.[0-9]+.*$')

    echo "$version"
}

#
# Size calculation helpers
#

# Convert bytes to human readable format
bytes_to_human() {
    local bytes="$1"
    if [ "$bytes" -ge 1048576 ]; then
        echo "$(( bytes / 1048576 ))M"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$(( bytes / 1024 ))K"
    else
        echo "${bytes}B"
    fi
}

# Round up to nearest sector boundary
align_to_sector() {
    local bytes="$1"
    local sector_size="${2:-$SECTOR_SIZE}"
    echo "$(( (bytes + sector_size - 1) / sector_size * sector_size ))"
}

# Convert sectors to bytes
sectors_to_bytes() {
    local sectors="$1"
    local sector_size="${2:-$SECTOR_SIZE}"
    echo "$(( sectors * sector_size ))"
}

# Convert bytes to sectors (rounded up)
bytes_to_sectors() {
    local bytes="$1"
    local sector_size="${2:-$SECTOR_SIZE}"
    echo "$(( (bytes + sector_size - 1) / sector_size ))"
}

#
# Container image helpers
#

# Get the full image reference (name:tag) for a container from the versions file
# Usage: get_container_image <versions_file> <container_name>
# e.g.: get_container_image versions-green.json supervisor
#        -> ghcr.io/home-assistant/aarch64-hassio-supervisor:2025.01.0
get_container_image() {
    local versions_file="$1"
    local container="$2"
    local image version
    image=$(jq -r ".images.${container}" "$versions_file")
    version=$(jq -r ".${container}" "$versions_file")
    if [ "$image" = "null" ] || [ -z "$image" ]; then
        die "No image pattern found for container: $container"
    fi
    if [ "$version" = "null" ] || [ -z "$version" ]; then
        die "No version found for container: $container"
    fi
    echo "${image}:${version}"
}

# Get just the image name (without tag) for a container
get_container_image_name() {
    local versions_file="$1"
    local container="$2"
    local image
    image=$(jq -r ".images.${container}" "$versions_file")
    if [ "$image" = "null" ] || [ -z "$image" ]; then
        die "No image pattern found for container: $container"
    fi
    echo "$image"
}

#
# Version source helpers
#

# Write the raw channel version JSON to stdout
# Reads VERSION_FILE (http(s) URL or local path) when set, otherwise
# VERSION_ENDPOINT/<channel>.json
fetch_version_json() {
    local channel="$1"

    if [ -n "$VERSION_FILE" ]; then
        case "$VERSION_FILE" in
            http://*|https://*)
                curl -fsSL "$VERSION_FILE"
                ;;
            *)
                require_file "$VERSION_FILE"
                cat "$VERSION_FILE"
                ;;
        esac
    else
        curl -fsSL "${VERSION_ENDPOINT}/${channel}.json"
    fi
}

#
# JSON helpers
#

# Extract value from JSON using jq
json_get() {
    local json_file="$1"
    local path="$2"
    jq -r "$path" "$json_file"
}

# Check if JSON file has a key
json_has() {
    local json_file="$1"
    local path="$2"
    jq -e "$path" "$json_file" >/dev/null 2>&1
}
