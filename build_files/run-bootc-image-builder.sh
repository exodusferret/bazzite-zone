#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 || $# -gt 7 ]]; then
    echo "usage: $0 <builder-image> <target-image> <type> <config-file> [output-dir] [rootfs] [chown]"
    exit 1
fi

builder_image="$1"
target_image="$2"
disk_type="$3"
config_file="$4"
output_dir="${5:-./output}"
rootfs="${6:-xfs}"
chown_spec="${7:-}"

retry() {
    local attempts="$1"
    shift

    local try
    for ((try = 1; try <= attempts; try++)); do
        if "$@"; then
            return 0
        fi

        if ((try == attempts)); then
            return 1
        fi

        echo "Attempt ${try}/${attempts} failed for: $*"
        sleep $((try * 10))
    done
}

mkdir -p "${output_dir}"

# Use a stable local tag after the remote pull so the build run does not
# re-negotiate the registry during `podman run`.
local_builder_image="localhost/bootc-image-builder:ci"

retry 3 sudo podman pull "${builder_image}"
sudo podman tag "${builder_image}" "${local_builder_image}"

if sudo podman image exists "${target_image}"; then
    echo "Using existing local target image: ${target_image}"
else
    retry 3 sudo podman pull "${target_image}"
fi

run_args=(
    --rm
    --privileged
    --pull=never
    --security-opt
    label=type:unconfined_t
    --volume
    /var/lib/containers/storage:/var/lib/containers/storage
    --volume
    "${output_dir}:/output"
    --volume
    "${config_file}:/config.toml:ro"
    "${local_builder_image}"
    --output
    /output
    --progress
    verbose
    --rootfs
    "${rootfs}"
    --use-librepo=True
    --type
    "${disk_type}"
)

if [[ -n "${chown_spec}" ]]; then
    run_args+=(
        --chown
        "${chown_spec}"
    )
fi

run_args+=("${target_image}")

sudo podman run "${run_args[@]}"
