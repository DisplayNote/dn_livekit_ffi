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

#ifndef LIVEKIT_X264_X264_VIDEO_ENCODER_H_
#define LIVEKIT_X264_X264_VIDEO_ENCODER_H_

#if defined(WEBRTC_USE_X264)

#include <memory>
#include <vector>

#include "api/video/video_codec_type.h"
#include "api/video/video_frame.h"
#include "api/video_codecs/video_encoder.h"
#include "rtc_base/synchronization/mutex.h"

extern "C" {
#include <x264.h>
}

namespace livekit {

class X264VideoEncoder : public webrtc::VideoEncoder {
 public:
  X264VideoEncoder();
  ~X264VideoEncoder() override;

  // VideoEncoder interface implementation
  int InitEncode(const webrtc::VideoCodec* codec_settings,
                 const webrtc::VideoEncoder::Settings& settings) override;

  int32_t RegisterEncodeCompleteCallback(
      webrtc::EncodedImageCallback* callback) override;

  int32_t Release() override;

  int32_t Encode(
      const webrtc::VideoFrame& frame,
      const std::vector<webrtc::VideoFrameType>* frame_types) override;

  void SetRates(const RateControlParameters& parameters) override;

  webrtc::VideoEncoder::EncoderInfo GetEncoderInfo() const override;

 private:
  struct X264Config {
    int width = 0;
    int height = 0;
    int target_bitrate_bps = 0;
    int max_framerate = 30;
    bool key_frame_requested = false;
  };

  bool InitializeEncoder();
  void DestroyEncoder();
  bool EncodeFrame(const webrtc::VideoFrame& frame, bool force_key_frame);

  // Threading and synchronization
  webrtc::Mutex encoder_mutex_;

  // X264 encoder context
  x264_t* encoder_ = nullptr;
  x264_param_t param_;
  x264_picture_t pic_in_;
  x264_picture_t pic_out_;

  // Configuration
  X264Config config_;
  bool initialized_ = false;
  int64_t first_frame_time_ms_ = -1;

  // Callback
  webrtc::EncodedImageCallback* encoded_image_callback_ = nullptr;

  // Frame counting for debugging
  int frame_count_ = 0;
};

// Factory function for creating X264VideoEncoder
std::unique_ptr<webrtc::VideoEncoder> CreateX264VideoEncoder();

}  // namespace livekit

#endif  // defined(WEBRTC_USE_X264) && defined(WEBRTC_ANDROID)

#endif  // LIVEKIT_X264_X264_VIDEO_ENCODER_H_