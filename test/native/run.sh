#!/bin/sh
# Builds and runs the native decoder tests on the host.
#
# PcmDecoder is pure byte handling with no Android dependency beyond logging,
# and its failure mode -- a byte order or sign read backwards -- is silent
# noise rather than a crash. That is worth checking without a phone, a DAC and
# a media server in the loop, which is all this needs.
set -e
here=$(dirname "$0")
cpp="$here/../../android/app/src/main/cpp"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

${CXX:-c++} -std=c++17 -Wall -Wextra \
    -I "$cpp" -I "$here/shim" \
    -o "$out/pcm_decoder_test" \
    "$here/pcm_decoder_test.cpp" "$cpp/decode/PcmDecoder.cpp"

"$out/pcm_decoder_test"
