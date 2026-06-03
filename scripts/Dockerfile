ARG CUDA_VERSION=12.6.3
ARG UBUNTU_VERSION=24.04
ARG BASE_IMAGE=nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION}

FROM ${BASE_IMAGE}

ARG CUDA_VERSION
ARG BASE_IMAGE
RUN echo "Base image: ${BASE_IMAGE:-default}" && \
    echo "CUDA_VERSION arg: ${CUDA_VERSION:-not set}" && \
    echo "Actual CUDA:" && (nvcc --version 2>/dev/null || echo "nvcc not found")

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
       g++ gcc git cmake ccache patch patchelf curl \
       ca-certificates \
       python3 python3-pip python3-dev python3-venv \
       doxygen graphviz \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --no-cache-dir --upgrade pip

COPY scripts/requirements.txt /tmp/ci-requirements.txt
RUN pip install --no-cache-dir -r /tmp/ci-requirements.txt && \
    rm /tmp/ci-requirements.txt

COPY python/test/requirements.txt /tmp/test-requirements.txt
RUN pip install --no-cache-dir -r /tmp/test-requirements.txt && \
    rm /tmp/test-requirements.txt

RUN mkdir -p /cuvslam
WORKDIR /cuvslam
