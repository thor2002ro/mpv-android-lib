#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include <memory>
#include <string>

#include <mpv/client.h>

#include "jni_utils.h"
#include "log.h"
#include "globals.h"
#include "node.h"
#include "mpv_context.h"

extern "C" {
    jni_func(jint, setOptionString, jstring option, jstring value);

    jni_func(jobject, getPropertyInt, jstring property);
    jni_func(void, setPropertyInt, jstring property, jint value);
    jni_func(jobject, getPropertyDouble, jstring property);
    jni_func(void, setPropertyDouble, jstring property, jdouble value);
    jni_func(jobject, getPropertyBoolean, jstring property);
    jni_func(void, setPropertyBoolean, jstring property, jboolean value);
    jni_func(jstring, getPropertyString, jstring jproperty);
    jni_func(void, setPropertyString, jstring jproperty, jstring jvalue);
    jni_func(jobject, getPropertyNode, jstring jproperty);
    jni_func(void, setPropertyNode, jstring jproperty, jobject jnode);

    jni_func(void, observeProperty, jstring property, jint format);
}

jni_func(jint, setOptionString, jstring joption, jstring jvalue) {
    MpvContext *ctx = get_context(env, obj);
    CHECK_CTX(ctx);

    const char *option = env->GetStringUTFChars(joption, NULL);
    const char *value = env->GetStringUTFChars(jvalue, NULL);

    int result = ctx->playback.run([&] { return mpv_set_option_string(ctx->mpv, option, value); });

    env->ReleaseStringUTFChars(joption, option);
    env->ReleaseStringUTFChars(jvalue, value);

    return result;
}

static int common_get_property(JNIEnv *env, MpvContext *ctx, jstring jproperty, mpv_format format, void *output)
{
    CHECK_CTX(ctx);

    const char *prop = env->GetStringUTFChars(jproperty, NULL);
    int result = ctx->playback.run([&] { return mpv_get_property(ctx->mpv, prop, format, output); });
    if (result == MPV_ERROR_PROPERTY_UNAVAILABLE)
        ALOGV("mpv_get_property(%s) format %d was unavailable", prop, format);
    else if (result < 0)
        ALOGE("mpv_get_property(%s) format %d returned error %s", prop, format, mpv_error_string(result));
    env->ReleaseStringUTFChars(jproperty, prop);

    return result;
}

template <typename T>
static void common_set_property(JNIEnv *env, MpvContext *ctx, jstring jproperty, mpv_format format, T value)
{
    CHECK_CTX(ctx);

    const char *prop = env->GetStringUTFChars(jproperty, NULL);
    if (!prop) return;
    std::string name(prop);
    env->ReleaseStringUTFChars(jproperty, prop);
    if (!ctx->playback.post([ctx, name, format, value]() mutable {
        int result = mpv_set_property(ctx->mpv, name.c_str(), format, &value);
        if (result < 0)
            ALOGE("mpv_set_property(%s) format %d returned error %s", name.c_str(), format, mpv_error_string(result));
    })) ALOGE("Unable to queue MPV property %s", name.c_str());
}

jni_func(jobject, getPropertyInt, jstring jproperty) {
    MpvContext *ctx = get_context(env, obj);
    int64_t value = 0;
    if (common_get_property(env, ctx, jproperty, MPV_FORMAT_INT64, &value) < 0)
        return NULL;
    return env->NewObject(java_Integer, java_Integer_init, (jint)value);
}

jni_func(jobject, getPropertyDouble, jstring jproperty) {
    MpvContext *ctx = get_context(env, obj);
    double value = 0;
    if (common_get_property(env, ctx, jproperty, MPV_FORMAT_DOUBLE, &value) < 0)
        return NULL;
    return env->NewObject(java_Double, java_Double_init, (jdouble)value);
}

jni_func(jobject, getPropertyBoolean, jstring jproperty) {
    MpvContext *ctx = get_context(env, obj);
    int value = 0;
    if (common_get_property(env, ctx, jproperty, MPV_FORMAT_FLAG, &value) < 0)
        return NULL;
    return env->NewObject(java_Boolean, java_Boolean_init, (jboolean)value);
}

jni_func(jstring, getPropertyString, jstring jproperty) {
    MpvContext *ctx = get_context(env, obj);
    char *value;
    if (common_get_property(env, ctx, jproperty, MPV_FORMAT_STRING, &value) < 0)
        return NULL;
    jstring jvalue = env->NewStringUTF(value);
    mpv_free(value);
    return jvalue;
}

jni_func(void, setPropertyInt, jstring jproperty, jint jvalue) {
    MpvContext *ctx = get_context(env, obj);
    int64_t value = static_cast<int64_t>(jvalue);
    common_set_property(env, ctx, jproperty, MPV_FORMAT_INT64, value);
}

jni_func(void, setPropertyDouble, jstring jproperty, jdouble jvalue) {
    MpvContext *ctx = get_context(env, obj);
    double value = static_cast<double>(jvalue);
    common_set_property(env, ctx, jproperty, MPV_FORMAT_DOUBLE, value);
}

jni_func(void, setPropertyBoolean, jstring jproperty, jboolean jvalue) {
    MpvContext *ctx = get_context(env, obj);
    int value = jvalue == JNI_TRUE ? 1 : 0;
    common_set_property(env, ctx, jproperty, MPV_FORMAT_FLAG, value);
}

jni_func(void, setPropertyString, jstring jproperty, jstring jvalue) {
    MpvContext *ctx = get_context(env, obj);
    CHECK_CTX(ctx);
    const char *value = env->GetStringUTFChars(jvalue, NULL);
    if (!value) return;
    const char *property = env->GetStringUTFChars(jproperty, NULL);
    if (!property) { env->ReleaseStringUTFChars(jvalue, value); return; }
    std::string name(property), text(value);
    env->ReleaseStringUTFChars(jproperty, property);
    env->ReleaseStringUTFChars(jvalue, value);
    if (!ctx->playback.post([ctx, name, text] {
        const char *value = text.c_str();
        int result = mpv_set_property(ctx->mpv, name.c_str(), MPV_FORMAT_STRING, &value);
        if (result < 0)
            ALOGE("mpv_set_property(%s) returned error %s", name.c_str(), mpv_error_string(result));
    })) ALOGE("Unable to queue MPV property %s", name.c_str());
}

jni_func(jobject, getPropertyNode, jstring jproperty) {
    MpvContext *ctx = get_context(env, obj);
    CHECK_CTX(ctx);

    const char *property = env->GetStringUTFChars(jproperty, NULL);

    mpv_node result;
    int error = ctx->playback.run([&] { return mpv_get_property(ctx->mpv, property, MPV_FORMAT_NODE, &result); });

    env->ReleaseStringUTFChars(jproperty, property);

    if (error < 0) return NULL;

    jobject jresult = mpv_node_to_jobject(env, &result);
    mpv_free_node_contents(&result);

    return jresult;
}

jni_func(void, setPropertyNode, jstring jproperty, jobject jnode) {
    MpvContext *ctx = get_context(env, obj);
    CHECK_CTX(ctx);

    const char *property = env->GetStringUTFChars(jproperty, NULL);

    mpv_node node;
    memset(&node, 0, sizeof(node));
    int parse_error = jobject_to_mpv_node(env, jnode, &node);

    if (parse_error == 0) {
        std::string name(property);
        auto owned = std::shared_ptr<mpv_node>(new mpv_node(node), [](mpv_node *value) {
            free_mpv_node(value);
            delete value;
        });
        if (!ctx->playback.post([ctx, name, owned] {
            int result = mpv_set_property(ctx->mpv, name.c_str(), MPV_FORMAT_NODE, owned.get());
            if (result < 0)
                ALOGE("mpv_set_property(%s) returned error %s", name.c_str(), mpv_error_string(result));
        })) ALOGE("Unable to queue MPV property %s", name.c_str());
    }

    env->ReleaseStringUTFChars(jproperty, property);
}

jni_func(void, observeProperty, jstring property, jint format) {
    MpvContext *ctx = get_context(env, obj);
    CHECK_CTX(ctx);
    const char *prop = env->GetStringUTFChars(property, NULL);
    int result = mpv_observe_property(ctx->mpv, 0, prop, (mpv_format)format);
    if (result < 0)
        ALOGE("mpv_observe_property(%s) format %d returned error %s", prop, format, mpv_error_string(result));
    env->ReleaseStringUTFChars(property, prop);
}
