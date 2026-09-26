cmake_minimum_required(VERSION 3.22.1)
project(hifirend LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_subdirectory(third_party/libusb)

add_library(hifirend SHARED
    hifirend.cpp
    Player.cpp
    StreamPlayer.cpp
    ToneSource.cpp
    decode/Decoder.cpp
    decode/DsdDecoder.cpp
    decode/FlacDecoder.cpp
    decode/Mp3Decoder.cpp
    decode/PcmDecoder.cpp
    usb/UacProbe.cpp
    usb/UacCapabilities.cpp
    usb/UsbSink.cpp
    sink/OboeSink.cpp
    AlacStream.cpp
    # Apple's reference ALAC decoder, Apache 2.0 -- see third_party/alac.
    # Vendored because this hardware has no platform ALAC decoder at all.
    third_party/alac/ALACDecoder.cpp
    third_party/alac/ALACBitUtilities.c
    third_party/alac/EndianPortable.c
    third_party/alac/ag_dec.c
    third_party/alac/dp_dec.c
    third_party/alac/matrix_dec.c
)

target_include_directories(hifirend PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

find_package(oboe REQUIRED CONFIG)

target_link_libraries(hifirend
    PRIVATE usb-1.0
            oboe::oboe
            log
            android
)
