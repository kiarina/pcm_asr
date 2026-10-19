// C shim over whisper.h for the Windows backend of pcm_asr. Dart never
// mirrors whisper_full_params / whisper_context_params (their layouts change
// between releases). Derived from the whisper_cpp package of the
// flutter-realtime-audio-analysis lab (MIT).
#pragma once

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define PAW_API __declspec(dllexport)
#else
#define PAW_API __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

PAW_API void paw_set_log_enabled(int enabled);
PAW_API void* paw_init_from_file(const char* path, int use_gpu);
PAW_API void paw_free(void* ctx);
// Returns 0 on success, 1 when aborted through *abort_flag, other values are
// whisper_full errors. pcm: 16 kHz mono float32 in [-1, 1]. abort_flag may be
// NULL; when it points at a non-zero int the decode stops as soon as possible.
PAW_API int paw_transcribe(void* ctx, const float* pcm, int n_samples, const char* language,
                           int n_threads, int no_context, int suppress_non_speech,
                           float temperature, const volatile int* abort_flag);
PAW_API int paw_n_segments(void* ctx);
PAW_API const char* paw_segment_text(void* ctx, int i);
// Segment times in units of 10 ms.
PAW_API int64_t paw_segment_t0(void* ctx, int i);
PAW_API int64_t paw_segment_t1(void* ctx, int i);
PAW_API const char* paw_result_language(void* ctx);
// 1 when ggml has a GPU device (Vulkan) compiled in and present, else 0.
PAW_API int paw_gpu_available(void);
PAW_API const char* paw_backend(void);
PAW_API const char* paw_system_info(void);

#ifdef __cplusplus
}
#endif
