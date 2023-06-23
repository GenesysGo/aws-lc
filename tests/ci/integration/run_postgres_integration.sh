#!/bin/bash -exu
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0 OR ISC

source tests/ci/common_posix_setup.sh

# Set up environment.

# SYS_ROOT
#  |
#  - SRC_ROOT(aws-lc)
#  |
#  - SCRATCH_FOLDER
#    |
#    - postgres
#    - AWS_LC_BUILD_FOLDER
#    - AWS_LC_INSTALL_FOLDER
#    - POSTGRES_BUILD_FOLDER

# Assumes script is executed from the root of aws-lc directory
SCRATCH_FOLDER=${SYS_ROOT}/"POSTGRES_BUILD_ROOT"
POSTGRES_SRC_FOLDER="${SCRATCH_FOLDER}/postgres"
POSTGRES_BUILD_FOLDER="${SCRATCH_FOLDER}/postgres/build"
AWS_LC_BUILD_FOLDER="${SCRATCH_FOLDER}/aws-lc-build"
AWS_LC_INSTALL_FOLDER="${POSTGRES_SRC_FOLDER}/aws-lc-install"

mkdir -p ${SCRATCH_FOLDER}
rm -rf ${SCRATCH_FOLDER}/*
cd ${SCRATCH_FOLDER}

function aws_lc_build() {
  ${CMAKE_COMMAND} ${SRC_ROOT} -GNinja "-B${AWS_LC_BUILD_FOLDER}" "-DCMAKE_INSTALL_PREFIX=${AWS_LC_INSTALL_FOLDER}"
  ninja -C ${AWS_LC_BUILD_FOLDER} install
  ls -R ${AWS_LC_INSTALL_FOLDER}
  rm -rf ${AWS_LC_BUILD_FOLDER}/*
}

function postgres_build() {
  ./configure --with-openssl --enable-tap-tests --with-includes=${AWS_LC_INSTALL_FOLDER}/include --with-libraries=${AWS_LC_INSTALL_FOLDER}/lib --prefix=$(pwd)/build
  make -j ${NUM_CPU_THREADS}
  # Build additional modules for postgres.
  make -j ${NUM_CPU_THREADS} -C contrib all
  ls -R build
}

function postgres_run_tests() {
  make -j ${NUM_CPU_THREADS} check
  # Run additional tests, particularly the "SSL" tests.
  make -j ${NUM_CPU_THREADS} check-world PG_TEST_EXTRA='ssl'
  cd ${SCRATCH_FOLDER}
}

# SSL tests expect the OpenSSL style of error messages. We patch this to expect AWS-LC's style.
# TODO: Remove this when we make an upstream contribution.
function postgres_patch() {
  POSTGRES_ERROR_STRING=("certificate verify failed" "bad decrypt" "sslv3 alert certificate revoked" "tlsv1 alert unknown ca")
  AWS_LC_EXPECTED_ERROR_STRING=("CERTIFICATE_VERIFY_FAILED" "BAD_DECRYPT" "SSLV3_ALERT_CERTIFICATE_REVOKED" "TLSV1_ALERT_UNKNOWN_CA")
  for i in "${!POSTGRES_ERROR_STRING[@]}"; do
    find ./ -type f -name "001_ssltests.pl" | xargs sed -i -e "s|${POSTGRES_ERROR_STRING[$i]}|${AWS_LC_EXPECTED_ERROR_STRING[$i]}|g"
  done
}

# Get latest postgres version.
git clone https://github.com/postgres/postgres.git ${POSTGRES_SRC_FOLDER}
mkdir -p ${AWS_LC_BUILD_FOLDER} ${AWS_LC_INSTALL_FOLDER} ${POSTGRES_BUILD_FOLDER}
ls

aws_lc_build
cd ${POSTGRES_SRC_FOLDER}
postgres_patch
postgres_build
postgres_run_tests
