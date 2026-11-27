#include "VisionInterface.h"
#include <Vision.h>

#include <cstring>
#include <string>

// Every argument is held to what the reader takes before it is called: zxing-cpp's image view
// throws on a picture that is none, and in the iOS app a catch of std::exception does not catch
// libc++'s exceptions (OfflineInterface.cpp) - so nothing is left for it to throw on.
int Vision_decodeQRCode(const unsigned char* gray, int width, int height, int rowStride, char* out, int outSize)
{
    if (!out || outSize <= 0) {
        return -1;
    }
    out[0] = '\0';
    if (!gray || width <= 0 || height <= 0 || rowStride < width) {
        return -1;
    }
    const std::string text = decodeQRCode(width, height, rowStride, ImageFormat::GRAY8, gray);
    if (text.empty()) {
        return 0;
    }
    if (text.size() >= static_cast<size_t>(outSize)) {
        return -1;
    }
    std::memcpy(out, text.data(), text.size());
    out[text.size()] = '\0';
    return static_cast<int>(text.size());
}
