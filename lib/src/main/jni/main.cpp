#include <jni.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#include <locale.h>
#include <atomic>
#include <string>
#include <vector>

#include <mpv/client.h>

#include <pthread.h>

extern "C" {
    #include <libavcodec/jni.h>
}

#include "log.h"
#include "jni_utils.h"
#include "event.h"
#include "node.h"
#include "mpv_context.h"

extern "C" {
    jni_func(void, nativeCreate, jobject appctx);
    jni_func(void, nativeInit);
    jni_func(void, nativeDestroy);

    jni_func(void, command, jobjectArray jarray);
    jni_func(jboolean, commandAsync, jlong request_id, jobjectArray jarray);
    jni_func(jobject, commandNode, jobjectArray jarray);
};

JavaVM *g_vm;

static bool environment_prepared = false;

static void prepare_environment(JNIEnv *env, jobject appctx) {
    if (environment_prepared)
        return;

    setlocale(LC_NUMERIC, "C");

    if (!env->GetJavaVM(&g_vm) && g_vm)
        av_jni_set_java_vm(g_vm, NULL);

    jobject global_appctx = env->NewGlobalRef(appctx);
    if (global_appctx)
        av_jni_set_android_app_ctx(global_appctx, NULL);

    init_methods_cache(env);
    environment_prepared = true;
}

jni_func(void, nativeCreate, jobject appctx) {
    prepare_environment(env, appctx);

    MpvContext *ctx = get_context(env, obj);
    if (ctx && ctx->mpv)
        die("mpv is already initialized for this instance");

    ctx = new MpvContext();
    ctx->mpv = mpv_create();
    if (!ctx->mpv) {
        delete ctx;
        die("context init failed");
    }

    // Store global reference to Java instance for callbacks
    ctx->java_instance = env->NewGlobalRef(obj);

    set_context(env, obj, ctx);

    // use terminal log level but request verbose messages
    // this way --msg-level can be used to adjust later
    mpv_request_log_messages(ctx->mpv, "terminal-default");
    mpv_set_option_string(ctx->mpv, "msg-level", "all=v");
}

jni_func(void, nativeInit) {
    MpvContext *ctx = get_context(env, obj);
    if (!ctx || !ctx->mpv)
        die("mpv is not created");

    if (mpv_initialize(ctx->mpv) < 0)
        die("mpv init failed");

    ctx->event_thread_request_exit = false;
    if (pthread_create(&ctx->event_thread_id, NULL, event_thread, ctx) != 0)
        die("thread create failed");
    pthread_setname_np(ctx->event_thread_id, "event_thread");
}

jni_func(void, nativeDestroy) {
    MpvContext *ctx = get_context(env, obj);
    if (!ctx || !ctx->mpv) {
        ALOGV("mpv destroy called but it's already destroyed");
        return;
    }

    // Drain playback work while the event consumer and handle are still alive.
    ctx->playback.stop();
    // Stop the only thread waiting on the handle before MPV tears down its core.
    ctx->event_thread_request_exit = true;
    mpv_wakeup(ctx->mpv);
    pthread_join(ctx->event_thread_id, NULL);

    mpv_terminate_destroy(ctx->mpv);

    // Delete global reference to Java instance
    if (ctx->java_instance) {
        env->DeleteGlobalRef(ctx->java_instance);
    }

    delete ctx;
    set_context(env, obj, nullptr);
}

static bool queue_command(JNIEnv *env, jobject obj, jobjectArray jarray, int64_t request_id) {
    MpvContext *ctx = get_context(env, obj);
    CHECK_CTX(ctx);

    int len = env->GetArrayLength(jarray);
    if (len == 0 || len >= 128) return false;
    std::vector<std::string> arguments;
    for (int i = 0; i < len; ++i) {
        jstring str = (jstring)env->GetObjectArrayElement(jarray, i);
        if (!str) return false;
        const char *value = env->GetStringUTFChars(str, NULL);
        if (!value) { env->DeleteLocalRef(str); return false; }
        arguments.emplace_back(value);
        env->ReleaseStringUTFChars(str, value);
        env->DeleteLocalRef(str);
    }
    return ctx->playback.post([ctx, arguments, request_id] {
        std::vector<const char *> argv;
        for (const auto &value : arguments) argv.push_back(value.c_str());
        argv.push_back(NULL);
        int error = mpv_command(ctx->mpv, argv.data());
        if (error >= 0) return;
        ALOGE("mpv_command(%s) returned error %s", argv[0], mpv_error_string(error));
        {
            std::lock_guard<std::mutex> lock(ctx->reply_mutex);
            ctx->command_failures.push_back({arguments[0], error, request_id});
        }
        mpv_wakeup(ctx->mpv);
    });
}

jni_func(void, command, jobjectArray jarray) {
    if (!queue_command(env, obj, jarray, 0)) ALOGE("Unable to queue MPV command");
}

jni_func(jboolean, commandAsync, jlong request_id, jobjectArray jarray) {
    return queue_command(env, obj, jarray, request_id) ? JNI_TRUE : JNI_FALSE;
}

jni_func(jobject, commandNode, jobjectArray jarray) {
    MpvContext *ctx = get_context(env, obj);
    CHECK_CTX(ctx);

    int len = env->GetArrayLength(jarray);
    if (len == 0) die("commandNode called with empty array");
    if (len > 128) die("commandNode called with too many arguments");

    mpv_node args;
    args.format = MPV_FORMAT_NODE_ARRAY;
    args.u.list = (mpv_node_list*)malloc(sizeof(mpv_node_list));
    args.u.list->num = len;
    args.u.list->values = (mpv_node*)malloc(len * sizeof(mpv_node));
    args.u.list->keys = NULL;

    for (int i = 0; i < len; ++i) {
        jstring jstr = (jstring)env->GetObjectArrayElement(jarray, i);
        const char *str = env->GetStringUTFChars(jstr, NULL);
        args.u.list->values[i].format = MPV_FORMAT_STRING;
        args.u.list->values[i].u.string = strdup(str);
        env->ReleaseStringUTFChars(jstr, str);
        env->DeleteLocalRef(jstr);
    }

    mpv_node result;
    int error = ctx->playback.run([&] { return mpv_command_node(ctx->mpv, &args, &result); });

    for (int i = 0; i < len; ++i) free(args.u.list->values[i].u.string);
    free(args.u.list->values);
    free(args.u.list);

    if (error < 0) return NULL;

    jobject jresult = mpv_node_to_jobject(env, &result);
    mpv_free_node_contents(&result);

    return jresult;
}
