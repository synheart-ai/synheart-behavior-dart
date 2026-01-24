cmake_minimum_required(VERSION 3.18.1)
project("flux_jni_bridge")

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Add the JNI bridge library
add_library(flux_jni_bridge SHARED
    flux_jni_bridge.cpp
)

# Find required libraries
find_library(log-lib log)
find_library(dl-lib dl)

# Link against system libraries
# Note: We use dlopen at runtime to access libsynheart_flux.so functions
# This avoids needing to link against it at build time
target_link_libraries(flux_jni_bridge
    ${log-lib}
    ${dl-lib}
)

# Include directories (if needed)
target_include_directories(flux_jni_bridge PRIVATE
    ${ANDROID_NDK}/sources/android/native_app_glue
)

