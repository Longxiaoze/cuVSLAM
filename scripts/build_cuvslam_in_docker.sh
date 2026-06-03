#!/bin/bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: ./scripts/build_cuvslam_in_docker.sh <CMAKE_BUILD_TYPE = Release | RelWithDebInfo> [output_dir]"
  echo ""
  echo "Environment variables (optional):"
  echo "  CUDA_VERSION    CUDA version for base image (default: 12.6.3)"
  echo "  UBUNTU_VERSION  Ubuntu version for base image (default: 24.04)"
  echo "  BASE_IMAGE      Override base Docker image (e.g. NGC Jetson image)"
  echo "  EXTRA_CMAKE_ARGS  Additional CMake arguments"
  exit 1
fi

BUILD_TYPE=$1
OUTPUT_DIR=${2:-$(pwd)/build_docker}
OUTPUT_DIR=$(realpath -m "$OUTPUT_DIR")
mkdir -p "$OUTPUT_DIR"

DOCKERFILE=$(dirname "$(realpath "$0")")/Dockerfile
DOCKER_BUILD_ARGS=""
[ -n "${CUDA_VERSION:-}" ] && DOCKER_BUILD_ARGS="$DOCKER_BUILD_ARGS --build-arg CUDA_VERSION=$CUDA_VERSION"
[ -n "${UBUNTU_VERSION:-}" ] && DOCKER_BUILD_ARGS="$DOCKER_BUILD_ARGS --build-arg UBUNTU_VERSION=$UBUNTU_VERSION"
[ -n "${BASE_IMAGE:-}" ] && DOCKER_BUILD_ARGS="$DOCKER_BUILD_ARGS --build-arg BASE_IMAGE=$BASE_IMAGE"
docker build -f "$DOCKERFILE" . --network host $DOCKER_BUILD_ARGS --tag cuvslam:local

INSTALL_DIR="/output"
DOCKER_VOLUMES="-v $(pwd):/cuvslam:ro -v $OUTPUT_DIR:$INSTALL_DIR"
DOCKER_USER="--user $(id -u):$(id -g) --group-add video -e HOME=/tmp"

TTY_FLAG=""
[ -t 0 ] && TTY_FLAG="-it"

docker run --runtime=nvidia --gpus all --rm $TTY_FLAG $DOCKER_USER $DOCKER_VOLUMES \
  -e CUVSLAM_SRC_DIR=/cuvslam \
  -e CUVSLAM_DST_DIR=$INSTALL_DIR/build \
  -e EXTRA_CMAKE_ARGS="${EXTRA_CMAKE_ARGS:-}" \
  cuvslam:local /cuvslam/build_release.sh --build_type="$BUILD_TYPE"
