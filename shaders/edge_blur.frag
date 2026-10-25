// A gradient blur of what is behind a band, one axis at a time (lib/art/edge_backdrop.dart): two of these, across
// then down, are one backdrop filter. The softness grows from none at the band's inner end to uSigma at its edge,
// and the blur is laid over the sharp view through a gradient mask that comes in over uFeather of the band.
//
// The mask is a clipping mask, the blurred layer's own opacity: the down pass, the last, gives each pixel the
// mask's share as its alpha (premultiplied), and the backdrop filter lays what it draws over the sharp view it read
// (a backdrop filter's layer goes onto what is behind it as srcOver), so a pixel is mix(sharp, blurred, mask). The
// across pass leaves its blur whole: had each pass mixed in the sharp view by the mask, the down pass would blur
// the across pass's own mix, and a row half in would be a quarter sharp, a quarter blurred across only and half a
// blur of the two, with words smeared down from the sharp rows under them.
#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

// Set by the engine: the size of the texture read, the screen's own pixels.
uniform vec2 uSize;
// The band on the screen, in its pixels: left, top, right, bottom.
uniform vec4 uBand;
// The softness at the band's edge, in the screen's pixels.
uniform float uSigma;
// Which edge of the band is softest: 0 its top, 1 its bottom, 2 its left, 3 its right.
uniform float uSide;
// Which way this pass blurs: 0 across, 1 down.
uniform float uAxis;
// How far in from the band's inner end the mask is whole, as a share of the band: none of the blur shows at the
// inner end, all of it from here to the edge, and a smoothstep between.
uniform float uFeather;

uniform sampler2D uTexture;

out vec4 fragColor;

// Taps each side of the middle one: the stride between them grows with the softness, so the cost is fixed.
const int kHalf = 16;

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 along = clamp((p - uBand.xy) / max(uBand.zw - uBand.xy, vec2(1.0)), 0.0, 1.0);
  float t = uSide < 0.5 ? 1.0 - along.y : (uSide < 1.5 ? along.y : (uSide < 2.5 ? 1.0 - along.x : along.x));
  float sigma = uSigma * t;
  vec2 uv = p / uSize;
  bool down = uAxis > 0.5;
  // The across pass is whole; the down pass is the blurred layer seen through the mask.
  float shown = down ? smoothstep(0.0, max(uFeather, 1e-3), t) : 1.0;
  if (shown <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  if (sigma < 0.5) {
    fragColor = texture(uTexture, uv) * shown;
    return;
  }
  vec2 dir = (down ? vec2(0.0, 1.0) : vec2(1.0, 0.0)) / uSize;
  float stride = max(1.0, 3.0 * sigma / float(kHalf));
  vec4 sum = texture(uTexture, uv);
  float weights = 1.0;
  float k = -0.5 / (sigma * sigma);
  for (int i = 1; i <= kHalf; i++) {
    float d = float(i) * stride;
    float w = exp(d * d * k);
    sum += (texture(uTexture, uv + dir * d) + texture(uTexture, uv - dir * d)) * w;
    weights += 2.0 * w;
  }
  fragColor = sum / weights * shown;
}
