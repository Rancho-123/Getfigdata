#include <metal_stdlib>
using namespace metal;

struct ColorUniforms {
    float h;
    float s;
    float v;
    float ht;
    float st;
    float vt;
    float minSat;
    float whiteThr;
};

inline float3 rgb2hsv(float3 c) {
    float maxc = max(c.r, max(c.g, c.b));
    float minc = min(c.r, min(c.g, c.b));
    float v = maxc;
    float s = maxc == 0.0 ? 0.0 : (maxc - minc) / maxc;
    float h = 0.0;
    float d = maxc - minc;
    if (d == 0.0) {
        h = 0.0;
    } else if (maxc == c.r) {
        h = (c.g - c.b) / d;
    } else if (maxc == c.g) {
        h = 2.0 + (c.b - c.r) / d;
    } else {
        h = 4.0 + (c.r - c.g) / d;
    }
    h /= 6.0;
    if (h < 0.0) h += 1.0;
    return float3(h, s, v);
}

kernel void colorMask(texture2d<float, access::read> src [[texture(0)]],
                      texture2d<float, access::write> mask [[texture(1)]],
                      constant ColorUniforms& uni [[buffer(0)]],
                      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= src.get_width() || gid.y >= src.get_height()) return;
    float4 p = src.read(gid);
    float3 c = float3(p.r, p.g, p.b);
    float3 hsv = rgb2hsv(c);
    float dh = min(fabs(hsv.x - uni.h), 1.0 - fabs(hsv.x - uni.h));
    float sd = fabs(hsv.y - uni.s);
    float vd = fabs(hsv.z - uni.v);
    bool isWhite = (hsv.y < 0.1) && (hsv.z > uni.whiteThr);
    // Dark lines can overlap with axes if they share color; keepDark relaxes saturation for very low Value targets.
    bool keepSat = (hsv.y >= uni.minSat) && !isWhite && (dh <= uni.ht) && (sd <= uni.st) && (vd <= uni.vt);
    bool keepDark = (uni.v < 0.25) && (hsv.z <= (uni.v + uni.vt));
    bool keep = keepSat || keepDark;
    float vout = keep ? 1.0 : 0.0;
    mask.write(float4(vout, 0.0, 0.0, 1.0), gid);
}

kernel void columnPeak(texture2d<float, access::read> mask [[texture(0)]],
                       device int2* out [[buffer(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    uint w = mask.get_width();
    if (gid.x >= w) return;
    int h = (int)mask.get_height();
    int yTop = -1;
    for (int y = 0; y < h; ++y) {
        float4 m = mask.read(uint2(gid.x, y));
        if (m.r > 0.5) { yTop = y; break; }
    }
    out[gid.x] = int2((int)gid.x, yTop);
}
