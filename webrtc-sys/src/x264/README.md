# X264 Video Encoder

This directory contains the implementation of `X264VideoEncoder`, a WebRTC `VideoEncoder` that uses the x264 library for H.264 encoding on Android platforms.

## Features

- **Hardware-optimized**: Configured for low-latency real-time encoding
- **Android-specific**: Only available when building for Android with x264 support
- **WebRTC compatible**: Implements the standard `webrtc::VideoEncoder` interface
- **Template adapter**: Includes adapter for use with `VideoEncoderFactoryTemplate`

## Build Requirements

1. **x264 library**: Must be available in the Android NDK environment
2. **Feature flag**: Enable the `use_x264` feature when building:
   ```bash
   cargo build --features use_x264
   ```
3. **Platform**: Only builds on Android targets

## Usage

### Direct Usage
```cpp
#include "livekit/x264/x264_video_encoder.h"

// Create encoder instance
auto encoder = livekit::CreateX264VideoEncoder();
```

### With VideoEncoderFactoryTemplate
```cpp
#include "livekit/x264/x264_encoder_template_adapter.h"

using MyFactory = webrtc::VideoEncoderFactoryTemplate<
    livekit::X264EncoderTemplateAdapter,
    webrtc::LibvpxVp8EncoderTemplateAdapter,
    webrtc::LibvpxVp9EncoderTemplateAdapter>;
```

## Configuration

The encoder is pre-configured for optimal real-time performance:

- **Preset**: `veryfast` with `zerolatency` tune
- **Profile**: H.264 Baseline
- **Rate Control**: Average Bitrate (ABR)
- **Key Frames**: Every 2 seconds maximum
- **B-frames**: Disabled for low latency
- **Threading**: Single-threaded for consistency

## Conditional Compilation

The entire implementation is wrapped in conditional compilation guards:

```cpp
#if defined(WEBRTC_USE_X264) && defined(WEBRTC_ANDROID)
// Implementation here
#endif
```

This ensures the code only compiles when:
1. `WEBRTC_USE_X264` is defined (set by the `use_x264` feature)
2. `WEBRTC_ANDROID` is defined (set for Android builds)

## Files

- `x264_video_encoder.h` - Header with class declaration
- `x264_video_encoder.cpp` - Implementation
- `x264_encoder_template_adapter.h` - Template adapter for factory integration
- `README.md` - This documentation

## Integration

The encoder integrates with the LiveKit WebRTC system and can be used as a drop-in replacement for other H.264 encoders in Android builds where x264 is available.