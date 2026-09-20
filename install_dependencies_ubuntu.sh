#!/usr/bin/env bash
set -euo pipefail

echo "============================================================"
echo " SU2 NEMO ONE-TIME UBUNTU DEPENDENCIES"
echo "============================================================"

sudo apt-get update
sudo apt-get install -y \
  build-essential \
  git \
  python3 \
  cmake \
  pkg-config \
  ninja-build \
  openmpi-bin \
  libopenmpi-dev \
  zlib1g-dev \
  curl \
  ca-certificates

echo "SU2_NEMO_DEPENDENCIES=PASS"
echo "Run this dependency installer only once per compatible machine."
