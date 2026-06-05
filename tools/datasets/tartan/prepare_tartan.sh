#!/usr/bin/env bash
# Download the TartanGround dataset and convert it to edex format by wrapping
# the existing provisioning + transform scripts.
#
# Usage: prepare_tartan.sh [OPTIONS]
#
# Options:
#   --raw-dir DIR        Directory to download into. Default: <repo>/datasets/tartan/raw
#   --output-dir DIR     Directory for converted data. Default: <repo>/datasets/converted
#   --variant NAME       'multisensor' or 'multicamera'. Default: multisensor
#   --force-download     Remove any existing download/conversion output first.
#   --download-only      Download but skip conversion.
#   -h, --help           Show this help.
#
# This wraps existing scripts and does not reimplement conversion:
#   examples/<variant>/download_tartan.py  download via the tartanair package
#   tools/tartanair_to_edex (dataset_converter)  sequences -> in-place edex + gt
#
# Note: dataset_converter only handles the classic TartanAir layout (image_left/
# image_right + pose_left.txt/pose_right.txt) and rewrites each sequence in
# place (image_left->00, image_right->01, gt.txt, cfg.edex). TartanGround
# downloads use a per-camera layout (lcam_*) the converter silently skips, so
# this script detects a compatible layout up front and fails loudly instead of
# reporting a no-op as success. Conversion runs on a staged copy under
# --output-dir so the raw download is preserved.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/../../.." && pwd -P)"

raw_dir="${repo_root}/datasets/tartan/raw"
output_dir="${repo_root}/datasets/converted"
variant="multisensor"
force_download=0
download_only=0

usage() {
    sed -n '2,/^$/p' "$0" | grep '^#' | sed 's/^# \?//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --raw-dir)
            [[ $# -lt 2 ]] && { echo "error: --raw-dir requires a value" >&2; exit 2; }
            raw_dir="$2"; shift 2 ;;
        --output-dir)
            [[ $# -lt 2 ]] && { echo "error: --output-dir requires a value" >&2; exit 2; }
            output_dir="$2"; shift 2 ;;
        --variant)
            [[ $# -lt 2 ]] && { echo "error: --variant requires a value" >&2; exit 2; }
            variant="$2"; shift 2 ;;
        --force-download)
            force_download=1; shift ;;
        --download-only)
            download_only=1; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            echo "error: unknown option '$1'" >&2; exit 2 ;;
    esac
done

echo "Raw dir    : ${raw_dir}"
echo "Output dir : ${output_dir}"
echo "Variant    : ${variant}"
echo ""

download_args=("${raw_dir}" --variant "${variant}")
[[ "${force_download}" -eq 1 ]] && download_args+=(--force)
bash "${script_dir}/download_tartan.sh" "${download_args[@]}"

[[ "${download_only}" -eq 1 ]] && exit 0

# Install the existing converter package if it is not importable.
if ! python3 -c "import dataset_converter" 2>/dev/null; then
    echo "installing dataset_converter (tools/tartanair_to_edex) …"
    python3 -m pip install "${repo_root}/tools/tartanair_to_edex"
fi

seq_path="${raw_dir}/dataset/tartan_ground"
converted_dir="${output_dir}/tartan/${variant}"

# Detect a converter-compatible sequence up front. dataset_converter walks for
# folders holding image_left/image_right + pose_left.txt/pose_right.txt and
# silently skips everything else (including the TartanGround lcam_* layout).
compatible=()
while IFS= read -r d; do
    [[ -d "${d}/image_right" && -f "${d}/pose_left.txt" && -f "${d}/pose_right.txt" ]] \
        && compatible+=("${d}")
done < <(find "${seq_path}" -type d -name image_left -exec dirname {} \; 2>/dev/null | sort -u || true)

if [[ "${#compatible[@]}" -eq 0 ]]; then
    echo "error: no classic-TartanAir sequences found under ${seq_path}." >&2
    echo "       dataset_converter requires image_left/image_right + pose_left.txt/pose_right.txt;" >&2
    echo "       the TartanGround per-camera layout (lcam_*) is not supported. Conversion skipped." >&2
    exit 1
fi

# dataset_converter rewrites each sequence in place, so work on a staged copy
# under --output-dir and keep it (it holds the converted result).
if [[ "${force_download}" -eq 1 ]]; then
    rm -rf -- "${converted_dir}"
fi
if [[ -e "${converted_dir}" ]]; then
    echo "error: ${converted_dir} already exists; use --force-download to overwrite" >&2
    exit 1
fi
mkdir -p "${converted_dir}"

echo ""
echo "Staging dataset copy …"
cp -a "${seq_path}/." "${converted_dir}/"

echo "Converting to edex …"
# --save_gt_folder/--save_edex_folder are required but unused for output (the
# converter writes in place); point them at fresh paths it can create.
python3 -m dataset_converter \
    --seq_path "${converted_dir}" \
    --save_gt_folder "${converted_dir}/.gt_unused" \
    --save_edex_folder "${converted_dir}/.edex_unused"

if ! find "${converted_dir}" -name cfg.edex -type f | grep -q .; then
    echo "error: conversion produced no cfg.edex under ${converted_dir}" >&2
    exit 1
fi

echo ""
echo "done — converted sequences (00/01 images, gt.txt, cfg.edex) under ${converted_dir}"
