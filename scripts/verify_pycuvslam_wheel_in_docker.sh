#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: ./scripts/verify_pycuvslam_wheel_in_docker.sh <build_output_dir>"
  echo "  Run after build_pycuvslam_in_docker.sh. Installs the repaired wheel into a"
  echo "  fresh environment and imports cuvslam, verifying the wheel filename is valid"
  echo "  (pip-installable) and the auditwheel-repaired extension loads with the"
  echo "  excluded CUDA libraries resolved from the system."
  exit 1
fi

OUTPUT_DIR=$(realpath "$1")

shopt -s nullglob
WHEELS=("$OUTPUT_DIR"/wheel/*.whl)
shopt -u nullglob

if [ "${#WHEELS[@]}" -eq 0 ]; then
  echo "Error: no wheel found in $OUTPUT_DIR/wheel."
  echo "Run './scripts/build_pycuvslam_in_docker.sh $OUTPUT_DIR' first."
  exit 1
elif [ "${#WHEELS[@]}" -gt 1 ]; then
  echo "Error: expected exactly one wheel in $OUTPUT_DIR/wheel, found ${#WHEELS[@]}:"
  printf '  %s\n' "${WHEELS[@]}"
  echo "Remove stale wheels (or rebuild into a clean output dir) before rerunning."
  exit 1
fi

WHEEL_NAME=$(basename "${WHEELS[0]}")

TTY_FLAG=""
[ -t 0 ] && TTY_FLAG="-it"

# --network host so pip can resolve the wheel's declared runtime deps (pyyaml).
# --system-site-packages keeps numpy/scipy from the image available so this stays a
# wheel-install/load smoke test rather than a full dependency-completeness audit.
docker run --runtime=nvidia --gpus all --rm $TTY_FLAG --network host \
  --user "$(id -u):$(id -g)" --group-add video -e HOME=/tmp \
  -v "$OUTPUT_DIR:/output:ro" \
  -e WHEEL_NAME="$WHEEL_NAME" \
  cuvslam:local bash -c '
    set -euo pipefail
    python3 -m venv --system-site-packages /tmp/wheel_venv
    . /tmp/wheel_venv/bin/activate
    pip install --no-cache-dir "/output/wheel/$WHEEL_NAME"
    cd /tmp
    python3 -c "import cuvslam; print(\"cuvslam wheel import OK, version:\", cuvslam.get_version())"
  '
