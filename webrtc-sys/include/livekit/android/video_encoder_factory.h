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

#pragma once

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "api/video_codecs/sdp_video_format.h"
#include "api/video_codecs/video_encoder_factory.h"

namespace livekit {

class AndroidVideoEncoderFactory : public webrtc::VideoEncoderFactory {
 public:
  // force_sw_h264: when true, H264 encoding prefers the SW MediaCodec encoder
  // (c2.android.avc.encoder) over the HW encoder.  Best-effort: falls back to
  // HW if the SW factory cannot be created (e.g., stale jar / missing ctor).
  // Effective on API 29+ only; on earlier APIs HW may still be selected.
  explicit AndroidVideoEncoderFactory(bool force_sw_h264 = false);
  ~AndroidVideoEncoderFactory() override;

  std::vector<webrtc::SdpVideoFormat> GetSupportedFormats() const override;

  CodecSupport QueryCodecSupport(
      const webrtc::SdpVideoFormat& format,
      std::optional<std::string> scalability_mode) const override;

  std::unique_ptr<webrtc::VideoEncoder> Create(
      const webrtc::Environment& env,
      const webrtc::SdpVideoFormat& format) override;

 private:
  bool IsH264Format(const webrtc::SdpVideoFormat& format) const;
  void EnsureH264InSupportedFormats(
      std::vector<webrtc::SdpVideoFormat>& formats) const;

  const std::unique_ptr<webrtc::VideoEncoderFactory> m_builtinEncoderFactory;
  std::unique_ptr<webrtc::VideoEncoderFactory> m_hwEncoderFactory;
  std::unique_ptr<webrtc::VideoEncoderFactory> m_swEncoderFactory;
  // Non-null when force_sw_h264=true — SW MediaCodec H264 encoder factory.
  std::unique_ptr<webrtc::VideoEncoderFactory> m_swH264EncoderFactory;
};

std::unique_ptr<webrtc::VideoEncoderFactory> CreateAndroidVideoEncoderFactory(
    bool force_sw_h264 = false);

}  // namespace livekit
