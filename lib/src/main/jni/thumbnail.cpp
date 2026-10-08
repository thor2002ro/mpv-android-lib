#include <stdlib.h>
#include <limits.h>
#include <string>

#include <jni.h>
#include <android/bitmap.h>
#include <mpv/client.h>

extern "C" {
    #include <libswscale/swscale.h>
    #include <libavutil/frame.h>
    #include <libavutil/opt.h>
    #include <libavutil/error.h>
};

#include "jni_utils.h"
#include "globals.h"
#include "log.h"
#include "mpv_context.h"

extern "C" {
    jni_func(jobject, grabThumbnail, jint dimension);
};

static inline mpv_node make_node_str(const char *s)
{
    mpv_node r{};
    r.format = MPV_FORMAT_STRING;
    r.u.string = const_cast<char*>(s);
    return r;
}

static int scale_thumbnail(const uint8_t *pixels, int width, int height, int stride,
                           uint8_t *output, int dimension)
{
    SwsContext *sws = sws_alloc_context();
    AVFrame *src = av_frame_alloc(), *dst = av_frame_alloc();
    if (!sws || !src || !dst) {
        sws_freeContext(sws);
        av_frame_free(&src);
        av_frame_free(&dst);
        return AVERROR(ENOMEM);
    }
    src->format = AV_PIX_FMT_BGR0;
    src->width = width;
    src->height = height;
    src->data[0] = const_cast<uint8_t *>(pixels);
    src->linesize[0] = stride;
    dst->format = AV_PIX_FMT_RGB32;
    dst->width = dst->height = dimension;
    dst->data[0] = output;
    dst->linesize[0] = dimension * sizeof(jint);
    src->colorspace = dst->colorspace = AVCOL_SPC_RGB;
    src->color_range = dst->color_range = AVCOL_RANGE_JPEG;
    int ret = av_opt_set_int(sws, "sws_flags", SWS_BICUBIC, 0);
    if (ret >= 0)
        ret = av_opt_set(sws, "sws_backends", "stable", 0);
    if (ret >= 0) {
        // JIT only covers same-size conversions; keep resizing on stable backends.
        if (width == dimension && height == dimension &&
            av_opt_set(sws, "sws_backends", "stable+arm_jit+aarch64_jit", 0) >= 0)
            av_opt_set_int(sws, "sws_flags", SWS_BICUBIC | SWS_UNSTABLE, 0);
        ret = sws_scale_frame(sws, dst, src);
    }
    sws_freeContext(sws);
    if (ret < 0) {
        sws = sws_getContext(width, height, AV_PIX_FMT_BGR0, dimension, dimension,
                             AV_PIX_FMT_RGB32, SWS_BICUBIC, NULL, NULL, NULL);
        if (sws) {
            const uint8_t *in[4] = {pixels};
            ret = sws_scale(sws, in, src->linesize, 0, height, dst->data, dst->linesize);
            ret = ret == dimension ? 0 : AVERROR_EXTERNAL;
            sws_freeContext(sws);
        }
    }
    av_frame_free(&src);
    av_frame_free(&dst);
    return ret;
}

jni_func(jobject, grabThumbnail, jint dimension) {
    MpvContext *ctx = get_context(env, obj);
    CHECK_CTX(ctx);
    if (dimension <= 0 || dimension > INT_MAX / dimension) {
        ALOGE("invalid thumbnail dimension");
        return NULL;
    }

    mpv_node result{};
    {
        mpv_node c{}, c_args[2];
        mpv_node_list c_array{};
        c_args[0] = make_node_str("screenshot-raw");
        c_args[1] = make_node_str("video");
        c_array.num = 2;
        c_array.values = c_args;
        c.format = MPV_FORMAT_NODE_ARRAY;
        c.u.list = &c_array;
        if (mpv_command_node(ctx->mpv, &c, &result) < 0) {
            ALOGE("screenshot-raw command failed");
            return NULL;
        }
    }

    // extract relevant property data from the node map mpv returns
    int64_t w = 0, h = 0, stride = 0;
    bool format_ok = false;
    struct mpv_byte_array *data = NULL;
    do {
        if (result.format != MPV_FORMAT_NODE_MAP)
            break;
        for (int i = 0; i < result.u.list->num; i++) {
            std::string key(result.u.list->keys[i]);
            const mpv_node *val = &result.u.list->values[i];
            if (key == "w" || key == "h" || key == "stride") {
                if (val->format != MPV_FORMAT_INT64)
                    break;
                if (key == "w")
                    w = val->u.int64;
                else if (key == "h")
                    h = val->u.int64;
                else
                    stride = val->u.int64;
            } else if (key == "format") {
                if (val->format != MPV_FORMAT_STRING)
                    break;
                format_ok = !strcmp(val->u.string, "bgr0");
            } else if (key == "data") {
                if (val->format != MPV_FORMAT_BYTE_ARRAY)
                    break;
                data = val->u.ba;
            }
        }
    } while (0);
    if (w <= 0 || h <= 0 || stride <= 0 || w > INT_MAX || h > INT_MAX ||
        stride > INT_MAX || stride < w * sizeof(uint32_t) || !format_ok || !data ||
        !data->data || data->size < (uint64_t)(h - 1) * stride + w * sizeof(uint32_t)) {
        ALOGE("extracting data failed");
        mpv_free_node_contents(&result);
        return NULL;
    }
    ALOGV("screenshot w:%d h:%d stride:%d", (int)w, (int)h, (int)stride);

    // crop to square
    int crop_left = 0, crop_top = 0;
    int new_w = w, new_h = h;
    if (w > h) {
        crop_left = (w - h) / 2;
        new_w = h;
    } else {
        crop_top = (h - w) / 2;
        new_h = w;
    }
    ALOGV("cropped w:%u h:%u", new_w, new_h);

    uint8_t *new_data = reinterpret_cast<uint8_t*>(data->data);
    new_data += crop_left * sizeof(uint32_t); // move begin rightwards
    new_data += stride * crop_top; // move begin downwards

    jintArray arr = env->NewIntArray(dimension * dimension);
    if (!arr) {
        mpv_free_node_contents(&result);
        return NULL;
    }
    jint *scaled = env->GetIntArrayElements(arr, NULL);
    if (!scaled) {
        mpv_free_node_contents(&result);
        env->DeleteLocalRef(arr);
        return NULL;
    }
    int ret = scale_thumbnail(new_data, new_w, new_h, stride,
                              reinterpret_cast<uint8_t *>(scaled), dimension);

    mpv_free_node_contents(&result); // frees data->data
    if (ret < 0) {
        ALOGE("thumbnail conversion failed: %d", ret);
        env->ReleaseIntArrayElements(arr, scaled, JNI_ABORT);
        env->DeleteLocalRef(arr);
        return NULL;
    }

    // create android.graphics.Bitmap
    env->ReleaseIntArrayElements(arr, scaled, 0);

    jobject bitmap_config =
        env->GetStaticObjectField(android_graphics_Bitmap_Config, android_graphics_Bitmap_Config_ARGB_8888);
    jobject bitmap =
        env->CallStaticObjectMethod(android_graphics_Bitmap, android_graphics_Bitmap_createBitmap,
        arr, dimension, dimension, bitmap_config);
    env->DeleteLocalRef(arr);
    env->DeleteLocalRef(bitmap_config);

    return bitmap;
}
