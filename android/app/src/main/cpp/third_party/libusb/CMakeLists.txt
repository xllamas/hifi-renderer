# libusb 1.0.28, built as a static library from exactly the source list in
# libusb's own android/jni/libusb.mk. Static because nothing outside the
# audio engine has any business talking to the DAC.
add_library(usb-1.0 STATIC
    libusb/core.c
    libusb/descriptor.c
    libusb/hotplug.c
    libusb/io.c
    libusb/sync.c
    libusb/strerror.c
    libusb/os/linux_usbfs.c
    libusb/os/events_posix.c
    libusb/os/threads_posix.c
    libusb/os/linux_netlink.c
)

target_include_directories(usb-1.0
    PUBLIC  ${CMAKE_CURRENT_SOURCE_DIR}/libusb
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}          # config.h
            ${CMAKE_CURRENT_SOURCE_DIR}/libusb/os
)

target_compile_options(usb-1.0 PRIVATE -fvisibility=hidden -Wno-unused-parameter)
target_link_libraries(usb-1.0 PRIVATE log)
set_target_properties(usb-1.0 PROPERTIES POSITION_INDEPENDENT_CODE ON)
