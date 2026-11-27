#ifndef VISION_INTERFACE_H_INCLUDED
#define VISION_INTERFACE_H_INCLUDED

#ifdef __cplusplus
extern "C" {
#endif

// The QR code in a grey picture, read by the engine's reader - dimx-vision's decodeQRCode,
// zxing-cpp, the reader Android's Live View reads codes with. `gray` is one byte a pixel,
// `width` by `height`, its rows `rowStride` bytes apart. The code's text goes into `out` as
// UTF-8 with its terminating zero. Answers the text's length; 0 where the picture shows no
// code; -1 where the picture is none or the text does not fit in `outSize`. Needs no engine
// running and is safe from any thread: the page's scanner reads its camera's pictures through
// it (PageQrDecoder.swift), the camera staying the page's.
int Vision_decodeQRCode(const unsigned char* gray, int width, int height, int rowStride, char* out, int outSize);

#ifdef __cplusplus
}
#endif

#endif // VISION_INTERFACE_H_INCLUDED
