/*
 * Copyright 2023 LiveKit
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "livekit/android/video_encoder_factory.h"

#include <jni.h>

#include <algorithm>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include "api/video_codecs/sdp_video_format.h"
#include "api/video_codecs/video_encoder_factory_template.h"
#include "api/video_codecs/video_encoder_factory_template_libvpx_vp8_adapter.h"
#include "api/video_codecs/video_encoder_factory_template_libvpx_vp9_adapter.h"
#include "media/base/media_constants.h"
#include "rtc_base/logging.h"
#include "sdk/android/native_api/base/init.h"
#include "sdk/android/native_api/codecs/wrapper.h"
#include "sdk/android/native_api/jni/class_loader.h"
#include "sdk/android/native_api/jni/scoped_java_ref.h"
#include "sdk/android/src/jni/jni_helpers.h"

#if defined(WEBRTC_USE_X264) && defined(WEBRTC_ANDROID)
#include "livekit/x264/x264_video_encoder.h"
#endif

#if defined(WEBRTC_USE_H264)
#include "api/video_codecs/video_encoder_factory_template_open_h264_adapter.h"
#endif

namespace livekit {

namespace {

std::unique_ptr<webrtc::VideoEncoderFactory> CreateHardwareVideoEncoderFactory() {
  JNIEnv* env = webrtc::AttachCurrentThreadIfNeeded();
  webrtc::ScopedJavaLocalRef<jclass> factory_class =
      webrtc::GetClass(env, "livekit/org/webrtc/HardwareVideoEncoderFactory");

  if (!factory_class.obj()) {
    RTC_LOG(LS_WARNING) << "HardwareVideoEncoderFactory class not found";
    return nullptr;
  }

  jmethodID ctor = env->GetMethodID(factory_class.obj(), "<init>",
                                    "(Llivekit/org/webrtc/EglBase$Context;ZZ)V");
  if (!ctor) {
    if (env->ExceptionCheck()) env->ExceptionClear();
    RTC_LOG(LS_WARNING) << "HardwareVideoEncoderFactory ctor not found";
    return nullptr;
  }

  jobject encoder_factory =
      env->NewObject(factory_class.obj(), ctor, nullptr, true, false);
  if (!encoder_factory) {
    if (env->ExceptionCheck()) env->ExceptionClear();
    RTC_LOG(LS_WARNING) << "Failed to instantiate HardwareVideoEncoderFactory";
    return nullptr;
  }
  return webrtc::JavaToNativeVideoEncoderFactory(env, encoder_factory);
}

// Creates a HardwareVideoEncoderFactory(null, false, false, null, allowSoftwareCodecs=true),
// which inverts the isHardwareAccelerated() check so only SW MediaCodec codecs are selected
// (e.g. c2.android.avc.encoder).  These produce standard H264 Baseline Level 3.1.
std::unique_ptr<webrtc::VideoEncoderFactory> CreateSoftwareH264VideoEncoderFactory() {
  JNIEnv* env = webrtc::AttachCurrentThreadIfNeeded();
  webrtc::ScopedJavaLocalRef<jclass> factory_class =
      webrtc::GetClass(env, "livekit/org/webrtc/HardwareVideoEncoderFactory");

  if (!factory_class.obj()) {
    RTC_LOG(LS_WARNING) << "HardwareVideoEncoderFactory class not found (SW H264)";
    return nullptr;
  }

  // (EglBase$Context, boolean, boolean, Predicate, boolean)
  jmethodID ctor = env->GetMethodID(
      factory_class.obj(), "<init>",
      "(Llivekit/org/webrtc/EglBase$Context;ZZLlivekit/org/webrtc/Predicate;Z)V");

  if (!ctor) {
    if (env->ExceptionCheck()) env->ExceptionClear();
    RTC_LOG(LS_WARNING) << "5-param HardwareVideoEncoderFactory ctor not found "
                           "— libwebrtc.jar may be stale; SW H264 factory unavailable";
    return nullptr;
  }

  jobject encoder_factory = env->NewObject(
      factory_class.obj(), ctor,
      /*sharedContext=*/nullptr,
      /*enableIntelVp8Encoder=*/static_cast<jboolean>(false),
      /*enableH264HighProfile=*/static_cast<jboolean>(false),
      /*codecAllowedPredicate=*/nullptr,
      /*allowSoftwareCodecs=*/static_cast<jboolean>(true));

  if (!encoder_factory) {
    if (env->ExceptionCheck()) env->ExceptionClear();
    RTC_LOG(LS_WARNING) << "Failed to instantiate SW H264 encoder factory";
    return nullptr;
  }
  return webrtc::JavaToNativeVideoEncoderFactory(env, encoder_factory);
}

std::unique_ptr<webrtc::VideoEncoderFactory> CreateSoftwareVideoEncoderFactory() {
  JNIEnv* env = webrtc::AttachCurrentThreadIfNeeded();
  webrtc::ScopedJavaLocalRef<jclass> factory_class =
      webrtc::GetClass(env, "livekit/org/webrtc/SoftwareVideoEncoderFactory");

  if (!factory_class.obj()) {
    RTC_LOG(LS_WARNING) << "SoftwareVideoEncoderFactory class not found";
    return nullptr;
  }

  jmethodID ctor = env->GetMethodID(factory_class.obj(), "<init>", "()V");
  if (!ctor) {
    if (env->ExceptionCheck()) env->ExceptionClear();
    RTC_LOG(LS_WARNING) << "SoftwareVideoEncoderFactory ctor not found";
    return nullptr;
  }

  jobject encoder_factory = env->NewObject(factory_class.obj(), ctor);
  if (!encoder_factory) {
    if (env->ExceptionCheck()) env->ExceptionClear();
    RTC_LOG(LS_WARNING) << "Failed to instantiate SoftwareVideoEncoderFactory";
    return nullptr;
  }
  return webrtc::JavaToNativeVideoEncoderFactory(env, encoder_factory);
}

}  // namespace

// AndroidVideoEncoderFactory implementation
AndroidVideoEncoderFactory::AndroidVideoEncoderFactory(bool force_sw_h264)
    : m_builtinEncoderFactory([]() {
        using Factory = webrtc::VideoEncoderFactoryTemplate<
            webrtc::LibvpxVp8EncoderTemplateAdapter,
#if defined(WEBRTC_USE_H264)
            webrtc::OpenH264EncoderTemplateAdapter,
#endif
            webrtc::LibvpxVp9EncoderTemplateAdapter>;
        return std::make_unique<Factory>();
      }()),
      m_hwEncoderFactory(CreateHardwareVideoEncoderFactory()),
      m_swEncoderFactory(CreateSoftwareVideoEncoderFactory()) {
  if (force_sw_h264) {
    m_swH264EncoderFactory = CreateSoftwareH264VideoEncoderFactory();
    if (m_swH264EncoderFactory) {
      RTC_LOG(LS_INFO) << "AndroidVideoEncoderFactory: force_sw_h264=true "
                          "— SW H264 encoder (c2.android.avc.encoder) will be used";
    } else {
      RTC_LOG(LS_WARNING) << "AndroidVideoEncoderFactory: force_sw_h264=true "
                             "but SW H264 factory unavailable — falling back to HW H264";
    }
  } else {
    RTC_LOG(LS_INFO) << "AndroidVideoEncoderFactory: force_sw_h264=false "
                        "— HW H264 encoder will be used";
  }
}

AndroidVideoEncoderFactory::~AndroidVideoEncoderFactory() {
  RTC_LOG(LS_INFO) << "AndroidVideoEncoderFactory destroyed";
}

bool AndroidVideoEncoderFactory::IsH264Format(
    const webrtc::SdpVideoFormat& format) const {
  return format.name == cricket::kH264CodecName;
}

void AndroidVideoEncoderFactory::EnsureH264InSupportedFormats(
    std::vector<webrtc::SdpVideoFormat>& formats) const {
  for (const auto& format : formats) {
    if (IsH264Format(format)) return;
  }

  webrtc::SdpVideoFormat h264_format(cricket::kH264CodecName);
  h264_format.parameters[cricket::kH264FmtpProfileLevelId] =
      cricket::kH264ProfileLevelConstrainedBaseline;
  formats.push_back(h264_format);
  RTC_LOG(LS_INFO) << "Added H.264 to supported formats";
}

std::vector<webrtc::SdpVideoFormat>
AndroidVideoEncoderFactory::GetSupportedFormats() const {
  std::vector<webrtc::SdpVideoFormat> formats;

  if (m_hwEncoderFactory) {
    for (const auto& fmt : m_hwEncoderFactory->GetSupportedFormats()) {
      // When SW H264 is forced, exclude HW H264 formats so SDP negotiation
      // cannot select a profile only the HW encoder supports.
      if (m_swH264EncoderFactory && IsH264Format(fmt)) continue;
      formats.push_back(fmt);
    }
  }
  if (m_swH264EncoderFactory) {
    auto sw_h264_formats = m_swH264EncoderFactory->GetSupportedFormats();
    formats.insert(formats.end(), sw_h264_formats.begin(), sw_h264_formats.end());
  }
  if (m_swEncoderFactory) {
    auto sw_formats = m_swEncoderFactory->GetSupportedFormats();
    formats.insert(formats.end(), sw_formats.begin(), sw_formats.end());
  }
  if (m_builtinEncoderFactory) {
    auto builtin_formats = m_builtinEncoderFactory->GetSupportedFormats();
    formats.insert(formats.end(), builtin_formats.begin(), builtin_formats.end());
  }

  // Skip synthetic H264 injection when the SW factory is active — it already
  // advertises its own H264 formats, and Create() never falls back to HW/x264
  // for H264 in that mode, so a synthetic entry could negotiate an unencodable format.
  if (!m_swH264EncoderFactory) {
    EnsureH264InSupportedFormats(formats);
  }

  // Sort by (name, parameters) so same-codec variants are adjacent for unique().
  std::sort(formats.begin(), formats.end(),
            [](const webrtc::SdpVideoFormat& a, const webrtc::SdpVideoFormat& b) {
              return a.name < b.name || (a.name == b.name && a.parameters < b.parameters);
            });
  formats.erase(std::unique(formats.begin(), formats.end(),
                            [](const webrtc::SdpVideoFormat& a,
                               const webrtc::SdpVideoFormat& b) {
                              return a.IsSameCodec(b);
                            }),
                formats.end());
  return formats;
}

webrtc::VideoEncoderFactory::CodecSupport
AndroidVideoEncoderFactory::QueryCodecSupport(
    const webrtc::SdpVideoFormat& format,
    std::optional<std::string> scalability_mode) const {
  if (IsH264Format(format) && m_swH264EncoderFactory) {
    return m_swH264EncoderFactory->QueryCodecSupport(format, scalability_mode);
  }

  if (m_hwEncoderFactory) {
    auto support = m_hwEncoderFactory->QueryCodecSupport(format, scalability_mode);
    if (support.is_supported) return support;
  }

  if (IsH264Format(format)) {
#if defined(WEBRTC_USE_X264) && defined(WEBRTC_ANDROID)
    return {.is_supported = true, .is_power_efficient = false};
#endif
  }

  if (m_swEncoderFactory) {
    auto support = m_swEncoderFactory->QueryCodecSupport(format, scalability_mode);
    if (support.is_supported) return support;
  }

  if (m_builtinEncoderFactory) {
    return m_builtinEncoderFactory->QueryCodecSupport(format, scalability_mode);
  }

  return {.is_supported = false};
}

std::unique_ptr<webrtc::VideoEncoder> AndroidVideoEncoderFactory::Create(
    const webrtc::Environment& env,
    const webrtc::SdpVideoFormat& format) {
  // When SW H264 is forced, route H264 directly to the SW factory and never
  // fall through to HW — even if the SW factory returns null.
  if (IsH264Format(format) && m_swH264EncoderFactory) {
    auto encoder = m_swH264EncoderFactory->Create(env, format);
    if (encoder) {
      RTC_LOG(LS_INFO) << "Created SW H264 encoder (force_sw_h264) for " << format.name;
    } else {
      RTC_LOG(LS_WARNING) << "SW H264 factory returned no encoder for " << format.name;
    }
    return encoder;
  }

  if (m_hwEncoderFactory) {
    for (const auto& supported_format : m_hwEncoderFactory->GetSupportedFormats()) {
      if (supported_format.IsSameCodec(format)) {
        auto encoder = m_hwEncoderFactory->Create(env, format);
        if (encoder) {
          RTC_LOG(LS_INFO) << "Created hardware encoder for " << format.name;
          return encoder;
        }
      }
    }
  }

  if (IsH264Format(format)) {
#if defined(WEBRTC_USE_X264) && defined(WEBRTC_ANDROID)
    RTC_LOG(LS_INFO) << "Creating X264VideoEncoder for H.264";
    return std::make_unique<X264VideoEncoder>();
#endif
  }

  if (m_swEncoderFactory) {
    for (const auto& supported_format : m_swEncoderFactory->GetSupportedFormats()) {
      if (supported_format.IsSameCodec(format)) {
        auto encoder = m_swEncoderFactory->Create(env, format);
        if (encoder) {
          RTC_LOG(LS_INFO) << "Created software encoder for " << format.name;
          return encoder;
        }
      }
    }
  }

  if (m_builtinEncoderFactory) {
    for (const auto& supported_format : m_builtinEncoderFactory->GetSupportedFormats()) {
      if (supported_format.IsSameCodec(format)) {
        auto encoder = m_builtinEncoderFactory->Create(env, format);
        if (encoder) {
          RTC_LOG(LS_INFO) << "Created builtin encoder for " << format.name;
          return encoder;
        }
      }
    }
  }

  RTC_LOG(LS_ERROR) << "No encoder found for " << format.name;
  return nullptr;
}

std::unique_ptr<webrtc::VideoEncoderFactory> CreateAndroidVideoEncoderFactory(
    bool force_sw_h264) {
  RTC_LOG(LS_INFO) << "Creating AndroidVideoEncoderFactory (force_sw_h264="
                   << force_sw_h264 << ")";
  return std::make_unique<AndroidVideoEncoderFactory>(force_sw_h264);
}

}  // namespace livekit
