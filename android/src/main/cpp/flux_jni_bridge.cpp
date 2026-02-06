#include <jni.h>
#include <string>
#include <cstring>
#include <dlfcn.h>
#include <android/log.h>

#define LOG_TAG "FluxJniBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Forward declarations for Rust C FFI functions
extern "C" {
    typedef char* (*flux_behavior_to_hsi_t)(const char* json);
    typedef void (*flux_free_string_t)(char* str);
    typedef char* (*flux_last_error_t)();
    typedef const char* (*flux_version_t)();
    typedef void* (*flux_behavior_processor_new_t)(int baseline_window);
    typedef void (*flux_behavior_processor_free_t)(void* processor);
    typedef char* (*flux_behavior_processor_process_t)(void* processor, const char* json);
    typedef char* (*flux_behavior_processor_save_baselines_t)(void* processor);
    typedef int (*flux_behavior_processor_load_baselines_t)(void* processor, const char* json);
}

// Function pointers (loaded once)
static flux_behavior_to_hsi_t g_flux_behavior_to_hsi = nullptr;
static flux_free_string_t g_flux_free_string = nullptr;
static flux_last_error_t g_flux_last_error = nullptr;
static flux_behavior_processor_new_t g_flux_behavior_processor_new = nullptr;
static flux_behavior_processor_free_t g_flux_behavior_processor_free = nullptr;
static flux_behavior_processor_process_t g_flux_behavior_processor_process = nullptr;
static flux_behavior_processor_save_baselines_t g_flux_behavior_processor_save_baselines = nullptr;
static flux_behavior_processor_load_baselines_t g_flux_behavior_processor_load_baselines = nullptr;
static flux_version_t g_flux_version = nullptr;
static bool g_functions_loaded = false;

// Load function pointers from libsynheart_flux.so
static bool load_flux_functions() {
    if (g_functions_loaded) {
        return true;
    }

    // libsynheart_flux.so should already be loaded by System.loadLibrary()
    // We can use dlopen with RTLD_LAZY | RTLD_NOLOAD to get handle to already loaded library
    void* handle = dlopen("libsynheart_flux.so", RTLD_LAZY | RTLD_NOLOAD);
    if (!handle) {
        // Try loading it explicitly
        handle = dlopen("libsynheart_flux.so", RTLD_LAZY);
    }

    if (!handle) {
        LOGE("Failed to load libsynheart_flux.so: %s", dlerror());
        return false;
    }

    // Load function pointers
    g_flux_behavior_to_hsi = (flux_behavior_to_hsi_t)dlsym(handle, "flux_behavior_to_hsi");
    g_flux_free_string = (flux_free_string_t)dlsym(handle, "flux_free_string");
    g_flux_last_error = (flux_last_error_t)dlsym(handle, "flux_last_error");
    g_flux_behavior_processor_new = (flux_behavior_processor_new_t)dlsym(handle, "flux_behavior_processor_new");
    g_flux_behavior_processor_free = (flux_behavior_processor_free_t)dlsym(handle, "flux_behavior_processor_free");
    g_flux_behavior_processor_process = (flux_behavior_processor_process_t)dlsym(handle, "flux_behavior_processor_process");
    g_flux_behavior_processor_save_baselines = (flux_behavior_processor_save_baselines_t)dlsym(handle, "flux_behavior_processor_save_baselines");
    g_flux_behavior_processor_load_baselines = (flux_behavior_processor_load_baselines_t)dlsym(handle, "flux_behavior_processor_load_baselines");
    g_flux_version = (flux_version_t)dlsym(handle, "flux_version");

    // Check if all required functions were loaded (flux_version is optional for backward compat)
    if (!g_flux_behavior_to_hsi || !g_flux_free_string || !g_flux_last_error ||
        !g_flux_behavior_processor_new || !g_flux_behavior_processor_free ||
        !g_flux_behavior_processor_process || !g_flux_behavior_processor_save_baselines ||
        !g_flux_behavior_processor_load_baselines) {
        LOGE("Failed to load some Flux functions");
        return false;
    }

    g_functions_loaded = true;
    LOGI("Successfully loaded all Flux functions");
    if (g_flux_version) {
        const char* ver = g_flux_version();
        if (ver) {
            LOGI("synheart-flux version: %s", ver);
        }
    }
    return true;
}

// Helper to convert jstring to C string
static char* jstring_to_cstring(JNIEnv* env, jstring jstr) {
    if (!jstr) {
        return nullptr;
    }
    const char* utf8 = env->GetStringUTFChars(jstr, nullptr);
    if (!utf8) {
        return nullptr;
    }
    size_t len = strlen(utf8);
    char* result = (char*)malloc(len + 1);
    if (result) {
        strcpy(result, utf8);
    }
    env->ReleaseStringUTFChars(jstr, utf8);
    return result;
}

// Helper to convert C string to jstring
static jstring cstring_to_jstring(JNIEnv* env, const char* cstr) {
    if (!cstr) {
        return nullptr;
    }
    return env->NewStringUTF(cstr);
}

// JNI: Java_ai_synheart_behavior_FluxBridge_nativeBehaviorToHsi
extern "C" JNIEXPORT jstring JNICALL
Java_ai_synheart_behavior_FluxBridge_nativeBehaviorToHsi(
    JNIEnv* env,
    jclass clazz,
    jstring json
) {
    if (!load_flux_functions()) {
        return nullptr;
    }

    char* json_cstr = jstring_to_cstring(env, json);
    if (!json_cstr) {
        return nullptr;
    }

    char* result_cstr = g_flux_behavior_to_hsi(json_cstr);
    free(json_cstr);

    if (!result_cstr) {
        // Get error message
        const char* error = g_flux_last_error();
        if (error) {
            LOGE("Flux error: %s", error);
        }
        return nullptr;
    }

    jstring result = cstring_to_jstring(env, result_cstr);
    g_flux_free_string(result_cstr);
    return result;
}

// JNI: Java_ai_synheart_behavior_FluxBridge_nativeProcessorNew
extern "C" JNIEXPORT jlong JNICALL
Java_ai_synheart_behavior_FluxBridge_nativeProcessorNew(
    JNIEnv* env,
    jclass clazz,
    jint baselineWindowSessions
) {
    if (!load_flux_functions()) {
        return 0;
    }

    void* processor = g_flux_behavior_processor_new(baselineWindowSessions);
    return reinterpret_cast<jlong>(processor);
}

// JNI: Java_ai_synheart_behavior_FluxBridge_nativeProcessorFree
extern "C" JNIEXPORT void JNICALL
Java_ai_synheart_behavior_FluxBridge_nativeProcessorFree(
    JNIEnv* env,
    jclass clazz,
    jlong handle
) {
    if (!load_flux_functions() || handle == 0) {
        return;
    }

    void* processor = reinterpret_cast<void*>(handle);
    g_flux_behavior_processor_free(processor);
}

// JNI: Java_ai_synheart_behavior_FluxBridge_nativeProcessorProcess
extern "C" JNIEXPORT jstring JNICALL
Java_ai_synheart_behavior_FluxBridge_nativeProcessorProcess(
    JNIEnv* env,
    jclass clazz,
    jlong handle,
    jstring json
) {
    if (!load_flux_functions() || handle == 0) {
        return nullptr;
    }

    char* json_cstr = jstring_to_cstring(env, json);
    if (!json_cstr) {
        return nullptr;
    }

    void* processor = reinterpret_cast<void*>(handle);
    char* result_cstr = g_flux_behavior_processor_process(processor, json_cstr);
    free(json_cstr);

    if (!result_cstr) {
        const char* error = g_flux_last_error();
        if (error) {
            LOGE("Flux error: %s", error);
        }
        return nullptr;
    }

    jstring result = cstring_to_jstring(env, result_cstr);
    g_flux_free_string(result_cstr);
    return result;
}

// JNI: Java_ai_synheart_behavior_FluxBridge_nativeProcessorSaveBaselines
extern "C" JNIEXPORT jstring JNICALL
Java_ai_synheart_behavior_FluxBridge_nativeProcessorSaveBaselines(
    JNIEnv* env,
    jclass clazz,
    jlong handle
) {
    if (!load_flux_functions() || handle == 0) {
        return nullptr;
    }

    void* processor = reinterpret_cast<void*>(handle);
    char* result_cstr = g_flux_behavior_processor_save_baselines(processor);

    if (!result_cstr) {
        const char* error = g_flux_last_error();
        if (error) {
            LOGE("Flux error: %s", error);
        }
        return nullptr;
    }

    jstring result = cstring_to_jstring(env, result_cstr);
    g_flux_free_string(result_cstr);
    return result;
}

// JNI: Java_ai_synheart_behavior_FluxBridge_nativeProcessorLoadBaselines
extern "C" JNIEXPORT jint JNICALL
Java_ai_synheart_behavior_FluxBridge_nativeProcessorLoadBaselines(
    JNIEnv* env,
    jclass clazz,
    jlong handle,
    jstring json
) {
    if (!load_flux_functions() || handle == 0) {
        return -1;
    }

    char* json_cstr = jstring_to_cstring(env, json);
    if (!json_cstr) {
        return -1;
    }

    void* processor = reinterpret_cast<void*>(handle);
    int result = g_flux_behavior_processor_load_baselines(processor, json_cstr);
    free(json_cstr);

    if (result != 0) {
        const char* error = g_flux_last_error();
        if (error) {
            LOGE("Flux error: %s", error);
        }
    }

    return result;
}

// JNI: Java_ai_synheart_behavior_FluxBridge_nativeFluxVersion
extern "C" JNIEXPORT jstring JNICALL
Java_ai_synheart_behavior_FluxBridge_nativeFluxVersion(
    JNIEnv* env,
    jclass clazz
) {
    if (!load_flux_functions() || !g_flux_version) {
        return nullptr;
    }
    const char* ver = g_flux_version();
    if (!ver) {
        return nullptr;
    }
    return cstring_to_jstring(env, ver);
}

// JNI: Java_ai_synheart_behavior_FluxBridge_nativeLastError
extern "C" JNIEXPORT jstring JNICALL
Java_ai_synheart_behavior_FluxBridge_nativeLastError(
    JNIEnv* env,
    jclass clazz
) {
    if (!load_flux_functions()) {
        return nullptr;
    }

    const char* error = g_flux_last_error();
    if (!error) {
        return nullptr;
    }

    return cstring_to_jstring(env, error);
}

