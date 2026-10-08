# Building

Compiling the native parts is a process separate from Gradle and the app won't work if you skip this.

The upstream scripts are supported on Linux and macOS. This project also
supports Windows through WSL2: run `build.bat` from the repository root. The
wrapper invokes `build.sh`, which stages the build on WSL's ext4 filesystem.

## Download dependencies

`download.sh` will take care of installing the Android SDK, NDK and downloading the sources.

If you're running on Debian/Ubuntu or RHEL/Fedora it will also install the necessary dependencies for you.

```sh
./download.sh
```

If you already have the Android SDK installed you can symlink `android-sdk-linux` to your SDK root
before running the script and the necessary SDK packages will still be installed.

A matching NDK version (inside the SDK) will be picked up automatically or downloaded and installed otherwise.

## Build

```sh
./buildall.sh
```

Run `buildall.sh` with `--clean` to clean the build directories before building.
For a guaranteed clean build also run `rm -rf prefix` beforehand.

By default this will build only for 32-bit ARM (`armv7l`).
You probably want to build for AArch64 too, and perhaps Intel x86.

To do this run one (or more) of these commands **before** ./buildall.sh:
```sh
./buildall.sh --arch arm64 mpv
./buildall.sh --arch x86 mpv
./buildall.sh --arch x86_64 mpv
```

# Developing

## Getting logs

```sh
adb logcat # get all logs, useful when drivers/vendor libs output to logcat
adb logcat -s mpv # get only mpv logs
```

## Rebuilding a single component

The FFmpeg download step applies `patches/ffmpeg/*.patch`. The Dolby Vision
patch configures the Android Dolby Vision MIME type and profile from the
stream's configuration record; HEVC without an RPU stays on the HEVC path.
Decoder lookup uses that Dolby Vision profile rather than the HEVC base-layer
profile. Unsupported Dolby Vision configurations fail instead of silently
opening an HDR10 decoder.

Local FFmpeg patches also forward Android color/HDR metadata and stop a
MediaCodec input/output busy loop after five seconds without progress. The
existing Dolby Vision profile is preserved. The MediaCodec buffer and HEVC
cleanup fixes from upstream PR #22550 are already in master.

ARM64 builds include the experimental [NEON JIT scaler proposal #23923](https://code.ffmpeg.org/FFmpeg/FFmpeg/pulls/23923)
with LLVM 21.1.8. Building it requires CMake 3.20 or newer and a host C++
compiler. LLVM assembler components are linked into libswscale; the existing
shared Android C++ runtime is required. Other ABIs do not build LLVM.

The JIT backend retains upstream runtime opt-in. A caller using the modern
`sws_scale_frame` API can allow it with `sws_backends=stable+aarch64_jit` on
ARM64 (or `SWS_UNSTABLE`); unsupported operations fall back to another allowed
backend.
MPV's current `sws_scale` path and this library's thumbnail code use the legacy
API and do not enter the JIT backend. Hardware decoding also bypasses this CPU
scaler. Enabling it for those callers requires a separate API migration and
playback/performance validation on the target ABI.

Additional ARM64 patches align threaded YUV-to-RGB slices to source chroma
(PR #24880), accelerate NAL start-code scanning with NEON (PR #21475), and
provide an explicit 10-bit VVC ALF gradient entry and the two-block classifier
(PR #24925). The NAL port preserves bounded reads and handles start codes at
buffer and vector boundaries. VVC decoding is already enabled; unsupported
ALF block dimensions retain the generic classifier.

ARMv7 builds use runtime-dispatched NEON NAL scanning, with the bounded C
scanner handling short buffers and candidate blocks. Clang also vectorizes
the existing 8-bit VVC ALF gradient loop; 10/12-bit processing and exact
64-bit direction decisions retain the compiler's existing implementation.
The ARMv7 YUV-to-RGB selector now supplies chroma-aligned slices and works
with the NDK integrated assembler; GNU-specific RGB-to-YUV routines retain
their existing assembler check. Conversion wrappers return the processed row
count, as required by the scaler API.

Focused checks (MediaCodec metadata requires a configured native-host
FFmpeg source tree with libavutil built):


If you've made changes to a single component (e.g. ffmpeg or mpv) and want a new build you can of course just run ./buildall.sh but it's also possible to just build a single component like this:

```sh
./buildall.sh -n ffmpeg
# optional: add --clean to build from a clean state
```

Note that you might need to rebuild for other architectures (`--arch`) too depending on your device.

Afterwards, build mpv-android and install the apk:

```sh
./buildall.sh -n
adb install -r ../lib/build/outputs/apk/default/debug/app-default-universal-debug.apk
```

## Using Android Studio

You can use Android Studio to develop the Java part of the codebase. Before using it, make sure to build the project at least once by following the steps in the **Build** section.

You should point Android Studio to existing SDK installation at `mpv-android/buildscripts/sdk/android-sdk-linux`.
Then click "Open an existing Android Studio project" and select `mpv-android`.

Note that if you build from Android Studio only the Java/Kotlin part will be built.
If you make any changes to libraries (ffmpeg, mpv, ...) or mpv-android native code (`lib/src/main/jni/*`), first rebuild native code with:

```sh
./buildall.sh -n
```

then build the project from Android Studio.
