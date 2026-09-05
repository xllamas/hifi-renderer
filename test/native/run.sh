#!/bin/sh
# Builds and runs the native audio tests on the host.
#
# Both units here fail silently rather than loudly, which is why they are worth
# testing without a phone, a DAC and a media server in the loop: PcmDecoder read
# the wrong way round produces noise, and a ToneSource that does not loop in
# phase produces a click -- and a click is indistinguishable from the dropout
# the rate sweep exists to detect.
set -e
here=$(dirname "$0")
cpp="$here/../../android/app/src/main/cpp"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

${CXX:-c++} -std=c++17 -Wall -Wextra \
    -I "$cpp" -I "$here/shim" \
    -o "$out/pcm_decoder_test" \
    "$here/pcm_decoder_test.cpp" "$cpp/decode/PcmDecoder.cpp"

${CXX:-c++} -std=c++17 -Wall -Wextra \
    -I "$cpp" -I "$here/shim" \
    -o "$out/tone_source_test" \
    "$here/tone_source_test.cpp" "$cpp/ToneSource.cpp"

"$out/pcm_decoder_test"
echo
"$out/tone_source_test"
