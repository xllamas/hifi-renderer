cmake_minimum_required(VERSION 3.22.1)
project(hifirend LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_subdirectory(third_party/libusb)

add_library(hifirend SHARED
    hifirend.cpp
    Player.cpp
    StreamPlayer.cpp
    decode/Decoder.cpp
    decode/FlacDecoder.cpp
    decode/Mp3Decoder.cpp
    usb/UacProbe.cpp
    usb/UacCapabilities.cpp
    usb/UsbSink.cpp
)

target_include_directories(hifirend PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

find_package(oboe REQUIRED CONFIG)

target_link_libraries(hifirend
    PRIVATE usb-1.0
            oboe::oboe
            log
            android
)
