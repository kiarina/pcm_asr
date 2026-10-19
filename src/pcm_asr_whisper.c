// See pcm_asr_whisper.h. All functions are called from one Dart background
// isolate per context; the shim keeps no global mutable state except the log
// switch and the backend description string.
#include "pcm_asr_whisper.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "whisper.h"
#include "ggml-backend.h"

static int g_log_enabled = -1;

static void paw_log_cb(enum ggml_log_level level, const char* text, void* user_data) {
  (void)user_data;
  if (g_log_enabled < 0) {
    const char* e = getenv("PCM_ASR_WHISPER_LOG");
    g_log_enabled = (e && e[0] == '1') ? 1 : 0;
  }
  if (g_log_enabled || level == GGML_LOG_LEVEL_ERROR) {
    fputs(text, stderr);
  }
}

PAW_API void paw_set_log_enabled(int enabled) {
  g_log_enabled = enabled;
  whisper_log_set(paw_log_cb, NULL);
}

PAW_API void* paw_init_from_file(const char* path, int use_gpu) {
  whisper_log_set(paw_log_cb, NULL);
  struct whisper_context_params p = whisper_context_default_params();
  p.use_gpu = use_gpu != 0;
  return whisper_init_from_file_with_params(path, p);
}

PAW_API void paw_free(void* ctx) {
  if (ctx) whisper_free((struct whisper_context*)ctx);
}

static bool paw_abort_cb(void* user_data) {
  const volatile int* flag = (const volatile int*)user_data;
  return flag && *flag != 0;
}

PAW_API int paw_transcribe(void* ctx, const float* pcm, int n_samples, const char* language,
                           int n_threads, int no_context, int suppress_non_speech,
                           float temperature, const volatile int* abort_flag) {
  struct whisper_full_params p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
  if (n_threads > 0) p.n_threads = n_threads;
  p.translate = false;
  p.no_context = no_context != 0;
  p.suppress_nst = suppress_non_speech != 0;
  p.temperature = temperature;
  p.language = (language && language[0]) ? language : "auto";
  p.detect_language = false;
  p.print_special = false;
  p.print_progress = false;
  p.print_realtime = false;
  p.print_timestamps = false;
  p.abort_callback = paw_abort_cb;
  p.abort_callback_user_data = (void*)abort_flag;
  int rc = whisper_full((struct whisper_context*)ctx, p, pcm, n_samples);
  if (abort_flag && *abort_flag) return 1;
  return rc == 0 ? 0 : (rc == 1 ? -1 : rc);
}

PAW_API int paw_n_segments(void* ctx) {
  return whisper_full_n_segments((struct whisper_context*)ctx);
}

PAW_API const char* paw_segment_text(void* ctx, int i) {
  return whisper_full_get_segment_text((struct whisper_context*)ctx, i);
}

PAW_API int64_t paw_segment_t0(void* ctx, int i) {
  return whisper_full_get_segment_t0((struct whisper_context*)ctx, i);
}

PAW_API int64_t paw_segment_t1(void* ctx, int i) {
  return whisper_full_get_segment_t1((struct whisper_context*)ctx, i);
}

PAW_API const char* paw_result_language(void* ctx) {
  int id = whisper_full_lang_id((struct whisper_context*)ctx);
  const char* s = id >= 0 ? whisper_lang_str(id) : NULL;
  return s ? s : "";
}

PAW_API int paw_gpu_available(void) {
  whisper_log_set(paw_log_cb, NULL);
  return ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_GPU) != NULL ? 1 : 0;
}

static char g_backend[256];

PAW_API const char* paw_backend(void) {
  if (g_backend[0]) return g_backend;
  const char* b =
#if defined(GGML_USE_VULKAN)
      "Vulkan, "
#endif
#if defined(GGML_USE_CUDA)
      "CUDA, "
#endif
#if defined(GGML_USE_BLAS)
      "BLAS, "
#endif
      "CPU";
  snprintf(g_backend, sizeof(g_backend), "whisper.cpp v%s (%s)", whisper_version(), b);
  return g_backend;
}

PAW_API const char* paw_system_info(void) {
  whisper_log_set(paw_log_cb, NULL);
  return whisper_print_system_info();
}
