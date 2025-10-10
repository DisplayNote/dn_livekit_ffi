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

#include "livekit/x264/x264_video_encoder.h"

#if defined(WEBRTC_USE_X264)

#include <algorithm>
#include <cstring>

#include "api/video/i420_buffer.h"
#include "common_video/libyuv/include/webrtc_libyuv.h"
#include "rtc_base/checks.h"
#include "rtc_base/logging.h"
#include "rtc_base/time_utils.h"
#include "modules/video_coding/include/video_error_codes.h"
#include "third_party/libyuv/include/libyuv.h"
#include "modules/video_coding/include/video_codec_interface.h"
#include "modules/video_coding/codecs/h264/include/h264_globals.h"
#include "modules/video_coding/codecs/interface/common_constants.h"

namespace livekit {

X264VideoEncoder::X264VideoEncoder() {
  RTC_LOG(LS_INFO) << "X264VideoEncoder created";
}

X264VideoEncoder::~X264VideoEncoder() {
  Release();
  RTC_LOG(LS_INFO) << "X264VideoEncoder destroyed";
}

int X264VideoEncoder::InitEncode(
    const webrtc::VideoCodec* codec_settings,
    const webrtc::VideoEncoder::Settings& settings) {
  RTC_LOG(LS_INFO) << "X264VideoEncoder::InitEncode";

  if (!codec_settings) {
    RTC_LOG(LS_ERROR) << "No codec settings provided";
    return WEBRTC_VIDEO_CODEC_ERR_PARAMETER;
  }

  if (codec_settings->codecType != webrtc::kVideoCodecH264) {
    RTC_LOG(LS_ERROR) << "Invalid codec type: " << codec_settings->codecType;
    return WEBRTC_VIDEO_CODEC_ERR_PARAMETER;
  }

  webrtc::MutexLock lock(&encoder_mutex_);

  // Store configuration
  config_.width = codec_settings->width;
  config_.height = codec_settings->height;
  config_.target_bitrate_bps =
      codec_settings->startBitrate * 1000;  // Convert to bps
  config_.max_framerate = codec_settings->maxFramerate;

  RTC_LOG(LS_INFO) << "Initializing x264 encoder: " << config_.width << "x"
                   << config_.height << " @ " << config_.target_bitrate_bps
                   << " bps, " << config_.max_framerate << " fps";

  // Initialize x264 encoder
  if (!InitializeEncoder()) {
    RTC_LOG(LS_ERROR) << "Failed to initialize x264 encoder";
    return WEBRTC_VIDEO_CODEC_ERROR;
  }

  initialized_ = true;
  first_frame_time_ms_ = -1;
  frame_count_ = 0;

  return WEBRTC_VIDEO_CODEC_OK;
}

int32_t X264VideoEncoder::RegisterEncodeCompleteCallback(
    webrtc::EncodedImageCallback* callback) {
  RTC_LOG(LS_INFO) << "X264VideoEncoder::RegisterEncodeCompleteCallback";
  webrtc::MutexLock lock(&encoder_mutex_);
  encoded_image_callback_ = callback;
  return WEBRTC_VIDEO_CODEC_OK;
}

int32_t X264VideoEncoder::Release() {
  RTC_LOG(LS_INFO) << "X264VideoEncoder::Release";
  webrtc::MutexLock lock(&encoder_mutex_);

  DestroyEncoder();
  encoded_image_callback_ = nullptr;
  initialized_ = false;

  return WEBRTC_VIDEO_CODEC_OK;
}

int32_t X264VideoEncoder::Encode(
    const webrtc::VideoFrame& frame,
    const std::vector<webrtc::VideoFrameType>* frame_types) {
  if (!initialized_) {
    RTC_LOG(LS_ERROR) << "Encoder not initialized";
    return WEBRTC_VIDEO_CODEC_UNINITIALIZED;
  }

  if (!encoded_image_callback_) {
    RTC_LOG(LS_ERROR) << "No encode callback registered";
    return WEBRTC_VIDEO_CODEC_UNINITIALIZED;
  }

  webrtc::MutexLock lock(&encoder_mutex_);

  if (first_frame_time_ms_ == -1) {
    first_frame_time_ms_ = rtc::TimeMillis();
  }

  // Check for key frame request
  bool force_key_frame = false;
  if (frame_types && !frame_types->empty()) {
    for (const auto& frame_type : *frame_types) {
      if (frame_type == webrtc::VideoFrameType::kVideoFrameKey) {
        force_key_frame = true;
        break;
      }
    }
  }

  if (!EncodeFrame(frame, force_key_frame)) {
    RTC_LOG(LS_ERROR) << "Failed to encode frame";
    return WEBRTC_VIDEO_CODEC_ERROR;
  }

  frame_count_++;
  return WEBRTC_VIDEO_CODEC_OK;
}

void X264VideoEncoder::SetRates(const RateControlParameters& parameters) {
  RTC_LOG(LS_INFO) << "X264VideoEncoder::SetRates - bitrate: "
                   << parameters.bitrate.get_sum_bps() << " bps";

  webrtc::MutexLock lock(&encoder_mutex_);

  if (!initialized_ || !encoder_) {
    return;
  }

  config_.target_bitrate_bps = parameters.bitrate.get_sum_bps();

  // Update x264 encoder bitrate
  x264_param_t param;
  x264_encoder_parameters(encoder_, &param);
  param.rc.i_bitrate = config_.target_bitrate_bps / 1000;  // Convert to kbps
  x264_encoder_reconfig(encoder_, &param);
}

webrtc::VideoEncoder::EncoderInfo X264VideoEncoder::GetEncoderInfo() const {
  webrtc::VideoEncoder::EncoderInfo info;
  info.supports_native_handle = false;
  info.implementation_name = "X264VideoEncoder";
  info.scaling_settings = webrtc::VideoEncoder::ScalingSettings::kOff;
  info.supports_simulcast = false;
  info.preferred_pixel_formats = {webrtc::VideoFrameBuffer::Type::kI420};
  return info;
}

bool X264VideoEncoder::InitializeEncoder() {
  if (encoder_) {
    DestroyEncoder();
  }

  // Set default parameters
  if (x264_param_default_preset(&param_, "veryfast", "zerolatency") < 0) {
    RTC_LOG(LS_ERROR) << "Failed to set x264 preset";
    return false;
  }

  // Configure parameters for real-time encoding
  param_.i_threads = 1;  // Single thread for consistency
  param_.i_width = config_.width;
  param_.i_height = config_.height;
  param_.i_fps_num = config_.max_framerate;
  param_.i_fps_den = 1;

  // Rate control
  param_.rc.i_rc_method = X264_RC_ABR;
  param_.rc.i_bitrate = config_.target_bitrate_bps / 1000;  // Convert to kbps
  param_.rc.i_vbv_max_bitrate = param_.rc.i_bitrate * 1.2;  // 20% overhead
  param_.rc.i_vbv_buffer_size = param_.rc.i_bitrate;        // 1 second buffer

  // Low latency settings
  param_.i_keyint_max = config_.max_framerate * 2;  // Key frame every 2 seconds
  param_.i_keyint_min = config_.max_framerate / 2;  // Minimum interval
  param_.b_intra_refresh = 1;
  param_.i_bframe = 0;  // No B-frames for low latency
  param_.b_cabac = 0;   // Faster encoding

  // Quality settings
  param_.analyse.i_me_method = X264_ME_DIA;  // Fast motion estimation
  param_.analyse.i_subpel_refine = 2;        // Faster subpixel refinement
  param_.analyse.b_mixed_references = 0;
  param_.analyse.b_chroma_me = 0;
  param_.analyse.b_fast_pskip = 1;

  // Apply profile constraints
  if (x264_param_apply_profile(&param_, "baseline") < 0) {
    RTC_LOG(LS_ERROR) << "Failed to apply x264 profile";
    return false;
  }

  // Open encoder
  encoder_ = x264_encoder_open(&param_);
  if (!encoder_) {
    RTC_LOG(LS_ERROR) << "Failed to open x264 encoder";
    return false;
  }

  // Allocate picture
  if (x264_picture_alloc(&pic_in_, X264_CSP_I420, config_.width,
                         config_.height) < 0) {
    RTC_LOG(LS_ERROR) << "Failed to allocate x264 picture";
    x264_encoder_close(encoder_);
    encoder_ = nullptr;
    return false;
  }

  RTC_LOG(LS_INFO) << "x264 encoder initialized successfully";
  return true;
}

void X264VideoEncoder::DestroyEncoder() {
  if (encoder_) {
    x264_picture_clean(&pic_in_);
    x264_encoder_close(encoder_);
    encoder_ = nullptr;
  }
}

bool X264VideoEncoder::EncodeFrame(const webrtc::VideoFrame& frame,
                                   bool force_key_frame) {
  if (!encoder_) {
    return false;
  }

  // Get I420 buffer
  rtc::scoped_refptr<webrtc::I420BufferInterface> i420_buffer =
      frame.video_frame_buffer()->ToI420();

  if (!i420_buffer) {
    RTC_LOG(LS_ERROR) << "Failed to convert frame to I420";
    return false;
  }

  // Check dimensions
  if (i420_buffer->width() != config_.width ||
      i420_buffer->height() != config_.height) {
    RTC_LOG(LS_ERROR) << "Frame size mismatch: expected " << config_.width
                      << "x" << config_.height << ", got "
                      << i420_buffer->width() << "x" << i420_buffer->height();
    return false;
  }

  // Copy frame data to x264 picture
  pic_in_.img.i_csp = X264_CSP_I420;
  pic_in_.img.i_plane = 3;

  // Y plane
  pic_in_.img.plane[0] = const_cast<uint8_t*>(i420_buffer->DataY());
  pic_in_.img.i_stride[0] = i420_buffer->StrideY();

  // U plane
  pic_in_.img.plane[1] = const_cast<uint8_t*>(i420_buffer->DataU());
  pic_in_.img.i_stride[1] = i420_buffer->StrideU();

  // V plane
  pic_in_.img.plane[2] = const_cast<uint8_t*>(i420_buffer->DataV());
  pic_in_.img.i_stride[2] = i420_buffer->StrideV();

  // Set frame properties
  pic_in_.i_pts = frame_count_;
  pic_in_.i_type = force_key_frame ? X264_TYPE_IDR : X264_TYPE_AUTO;

  // Encode frame
  x264_nal_t* nals = nullptr;
  int i_nals = 0;
  int frame_size =
      x264_encoder_encode(encoder_, &nals, &i_nals, &pic_in_, &pic_out_);

  if (frame_size < 0) {
    RTC_LOG(LS_ERROR) << "x264_encoder_encode failed";
    return false;
  }

  if (frame_size == 0) {
    // No output frame (delayed)
    return true;
  }

  // Process encoded frame
  bool is_key_frame = (pic_out_.i_type == X264_TYPE_IDR);

  // Combine all NAL units
  std::vector<uint8_t> encoded_data;
  for (int i = 0; i < i_nals; i++) {
    encoded_data.insert(encoded_data.end(), nals[i].p_payload,
                        nals[i].p_payload + nals[i].i_payload);
  }

  // Create encoded image
  webrtc::EncodedImage encoded_image;
  encoded_image.SetEncodedData(webrtc::EncodedImageBuffer::Create(
      encoded_data.data(), encoded_data.size()));
  encoded_image._encodedWidth = config_.width;
  encoded_image._encodedHeight = config_.height;
  encoded_image.SetRtpTimestamp(static_cast<uint32_t>(frame.timestamp_us()));
  encoded_image.ntp_time_ms_ = frame.ntp_time_ms();
  encoded_image.capture_time_ms_ = frame.render_time_ms();
  encoded_image._frameType = is_key_frame
                                 ? webrtc::VideoFrameType::kVideoFrameKey
                                 : webrtc::VideoFrameType::kVideoFrameDelta;
  encoded_image.content_type_ = webrtc::VideoContentType::UNSPECIFIED;
  encoded_image.timing_.flags = webrtc::VideoSendTiming::kInvalid;

  // Send encoded frame
  webrtc::CodecSpecificInfo codec_specific;
  codec_specific.codecType = webrtc::kVideoCodecH264;
  codec_specific.codecSpecific.H264.packetization_mode =
      webrtc::H264PacketizationMode::NonInterleaved;
  codec_specific.codecSpecific.H264.temporal_idx = webrtc::kNoTemporalIdx;
  codec_specific.codecSpecific.H264.idr_frame = is_key_frame;
  codec_specific.codecSpecific.H264.base_layer_sync = false;

  webrtc::EncodedImageCallback::Result result =
      encoded_image_callback_->OnEncodedImage(encoded_image, &codec_specific);

  if (result.error != webrtc::EncodedImageCallback::Result::OK) {
    RTC_LOG(LS_ERROR) << "Encode callback failed with error: " << result.error;
    return false;
  }

  RTC_LOG(LS_VERBOSE) << "Encoded frame " << frame_count_ << " ("
                      << (is_key_frame ? "key" : "delta") << ") - "
                      << encoded_data.size() << " bytes";

  return true;
}

std::unique_ptr<webrtc::VideoEncoder> CreateX264VideoEncoder() {
  return std::make_unique<X264VideoEncoder>();
}

}  // namespace livekit

#endif  // defined(WEBRTC_USE_X264) && defined(WEBRTC_ANDROID)