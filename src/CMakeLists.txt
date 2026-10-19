# Builds whisper.cpp + ggml as static libraries and links them with the C
# shim into one shared library `pcm_asr_whisper`. Used by windows/CMakeLists.txt.
# Run tool/fetch_whisper_cpp.sh before the first build (third_party/whisper.cpp
# is not vendored).
cmake_minimum_required(VERSION 3.14)

project(pcm_asr_whisper_library VERSION 0.0.1 LANGUAGES C CXX)

set(PAW_WHISPER_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/whisper.cpp"
    CACHE PATH "whisper.cpp source tree")
if (NOT EXISTS "${PAW_WHISPER_DIR}/include/whisper.h")
  message(FATAL_ERROR
    "whisper.cpp sources not found at ${PAW_WHISPER_DIR}. "
    "Run tool/fetch_whisper_cpp.sh in the pcm_asr package first.")
endif()

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

set(WHISPER_BUILD_TESTS    OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER   OFF CACHE BOOL "" FORCE)
set(WHISPER_CURL           OFF CACHE BOOL "" FORCE)
set(WHISPER_SDL2           OFF CACHE BOOL "" FORCE)
set(WHISPER_ALL_WARNINGS   OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_IS_DEV   OFF CACHE BOOL "" FORCE)

# Portable binaries: never -march=native. OpenMP off (ggml's own thread pool).
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)

if (WIN32 AND CMAKE_SYSTEM_PROCESSOR MATCHES "^(AMD64|x86_64|x64)$")
  # x64 CPU with AVX2 (Haswell+ / Zen+). No GPU backend: Vulkan would need the
  # Vulkan SDK at build time. The DLL depends only on the MSVC runtime.
  set(GGML_AVX  ON CACHE BOOL "" FORCE)
  set(GGML_AVX2 ON CACHE BOOL "" FORCE)
  set(GGML_FMA  ON CACHE BOOL "" FORCE)
  set(GGML_F16C ON CACHE BOOL "" FORCE)
  set(GGML_BMI2 ON CACHE BOOL "" FORCE)
  set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
  set(GGML_CUDA   OFF CACHE BOOL "" FORCE)
  set(GGML_BLAS   OFF CACHE BOOL "" FORCE)
endif()

add_subdirectory("${PAW_WHISPER_DIR}" whisper.cpp EXCLUDE_FROM_ALL)

add_library(pcm_asr_whisper SHARED "pcm_asr_whisper.c")
target_link_libraries(pcm_asr_whisper PRIVATE whisper)
set_target_properties(pcm_asr_whisper PROPERTIES OUTPUT_NAME "pcm_asr_whisper")
target_compile_definitions(pcm_asr_whisper PUBLIC DART_SHARED_LIB)
