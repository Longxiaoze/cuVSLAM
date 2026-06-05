#!/usr/bin/env bash
# Download the TartanGround dataset by wrapping the existing example
# download_tartan.py provisioning script.
#
# Usage: download_tartan.sh [OPTIONS] [OUT_DIR]
#
#   OUT_DIR              Directory to download into. The tartanair package
#                        creates <OUT_DIR>/dataset/tartan_ground/...
#                        Defaults to <repo_root>/datasets/tartan/raw
#   --variant NAME       Which example download script to run:
#                        'multisensor' (2 cams + depth + imu) or
#                        'multicamera' (12 cams, image only).
#                        Default: multisensor
#   --skip-install       Do not pip install the tartanair package if missing.
#   --force              Remove any existing tartan_ground download first.
#
# Note: the tartanair package only works on x86_64. On aarch64 (e.g. Jetson)
# it fails at import; download on x86_64 and transfer the data to the target.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/../../.." && pwd -P)"
out_dir="${repo_root}/datasets/tartan/raw"
variant="multisensor"
skip_install=0
force=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant)
            [[ $# -lt 2 ]] && { echo "error: --variant requires a value" >&2; exit 2; }
            variant="$2"; shift 2 ;;
        --skip-install) skip_install=1; shift ;;
        --force) force=1; shift ;;
        -*) echo "error: unknown option '$1'" >&2; exit 2 ;;
        *)  out_dir="$1"; shift ;;
    esac
done

case "${variant}" in
    multisensor) example_dir="${repo_root}/examples/multisensor" ;;
    multicamera) example_dir="${repo_root}/examples/multicamera_edex" ;;
    *) echo "error: unknown variant '${variant}' (expected multisensor|multicamera)" >&2; exit 2 ;;
esac

download_script="${example_dir}/download_tartan.py"
if [[ ! -f "${download_script}" ]]; then
    echo "error: provisioning script not found: ${download_script}" >&2
    exit 1
fi

if [[ "${skip_install}" -eq 0 ]] && ! python3 -c "import tartanair" 2>/dev/null; then
    echo "tartanair package not found — installing …"
    python3 -m pip install tartanair
fi

mkdir -p "${out_dir}"
[[ "${force}" -eq 1 ]] && rm -rf -- "${out_dir}/dataset/tartan_ground"

echo "running ${download_script} (variant: ${variant}) …"
# download_tartan.py writes to a relative 'dataset/tartan_ground/' path, so run
# it with OUT_DIR as the working directory.
( cd "${out_dir}" && python3 "${download_script}" )

echo "done — files saved under ${out_dir}/dataset/tartan_ground"
