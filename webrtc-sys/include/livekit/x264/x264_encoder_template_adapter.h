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

#ifndef LIVEKIT_X264_X264_ENCODER_TEMPLATE_ADAPTER_H_
#define LIVEKIT_X264_X264_ENCODER_TEMPLATE_ADAPTER_H_

#if defined(WEBRTC_USE_X264)

#include <memory>
#include <vector>

#include "api/video_codecs/sdp_video_format.h"
#include "api/video_codecs/video_encoder.h"
#include "livekit/x264/x264_video_encoder.h"
#include "media/base/media_constants.h"

namespace livekit {

// Template adapter for integrating X264VideoEncoder with
// VideoEncoderFactoryTemplate
struct X264EncoderTemplateAdapter {
  static std::vector<webrtc::SdpVideoFormat> SupportedFormats() {
    return {
        webrtc::SdpVideoFormat(cricket::kH264CodecName,
                               {{cricket::kH264FmtpProfileLevelId,
                                 cricket::kH264ProfileLevelConstrainedBaseline},
                                {cricket::kH264FmtpLevelAsymmetryAllowed, "1"},
                                {cricket::kH264FmtpPacketizationMode, "1"}})};
  }

  static std::unique_ptr<webrtc::VideoEncoder> CreateEncoder(
      const webrtc::SdpVideoFormat& format) {
    return CreateX264VideoEncoder();
  }

  static bool IsScalabilityModeSupported(
      webrtc::ScalabilityMode scalability_mode) {
    return scalability_mode == webrtc::ScalabilityMode::kL1T1;
  }
};

}  // namespace livekit

#endif  // defined(WEBRTC_USE_X264) && defined(WEBRTC_ANDROID)

#endif  // LIVEKIT_X264_X264_ENCODER_TEMPLATE_ADAPTER_H_