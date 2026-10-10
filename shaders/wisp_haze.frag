#version 460 core

// What is soft in a wisp's smoke, made small: `soft` (the bent view under `feGaussianBlur`) kept to `near` (the bent
// view under `feMorphology`'s dilate), the two primitives of art/WispEdgeFilter.tsx between `bent` and the merge.
//
// A blur has no detail finer than itself, so it is worked out on a picture of the bent view a half or a quarter of
// the screen's size (shaders/wisp_bend.frag drawn small) and read back up by the last pass (shaders/wisp_smoke.frag).
// The blur is the Gaussian itself over thirteen of the small picture's pixels each way, every pixel weighted as the
// curve has it: the middle one read by itself and the six either side in pairs, each pair read once at the point
// between the two that weighs them as they should be (lib/art/wisp_smoke.dart `wispBlurTaps` works the points and
// weights out). Taps laid at any other spacing weigh some pixels heavily and their neighbours hardly, and the
// bent strokes came through the blur as a grid of dots: static, where smoke was meant. The dilate is the most ink
// on a grid of taps over its box, as wisp_merge.frag reads it.

#include <flutter/runtime_effect.glsl>

precision highp float;

// The drawn rectangle's corner in the view's own pixels.
uniform vec2 uOrigin;
// Where uBent lies in the view: left, top, width, height.
uniform vec4 uBentRect;
// The part of it that is this smoke's own, clear outside it as a primitive's subregion is: all of it for a strip's
// picture, one letter's place on a sheet of many (lib/art/wisp_letters.dart).
uniform vec4 uOwn;
// One pixel of uBent, in the view's pixels.
uniform vec2 uTexel;
// Where the three pairs either side of the middle are read, in uBent's pixels from it.
uniform vec3 uOffsets;
// What the middle pixel and each pair weigh. The middle and twice the pairs sum to one.
uniform vec4 uWeights;
// `feMorphology` dilate's radius, across and down, in the view's pixels.
uniform vec2 uNear;
// What the ink found near a point is multiplied by: the small picture has a thin stroke at a part of its ink.
// Nothing: no dilate is asked for, and the blur is whole wherever it falls (a letter's filter has none).
uniform float uGain;

uniform sampler2D uBent;

out vec4 fragColor;

vec4 bentAt(vec2 p) {
  if (p.x < uOwn.x || p.y < uOwn.y || p.x >= uOwn.x + uOwn.z || p.y >= uOwn.y + uOwn.w) {
    return vec4(0.0);
  }
  return texture(uBent, (p - uBentRect.xy) / uBentRect.zw);
}

// One row of the blur: the middle pixel and three pairs either side.
vec4 wispRow(vec2 p) {
  vec3 dx = uOffsets * uTexel.x;
  vec4 sum = uWeights.x * bentAt(p);
  sum += uWeights.y * (bentAt(p - vec2(dx.x, 0.0)) + bentAt(p + vec2(dx.x, 0.0)));
  sum += uWeights.z * (bentAt(p - vec2(dx.y, 0.0)) + bentAt(p + vec2(dx.y, 0.0)));
  sum += uWeights.w * (bentAt(p - vec2(dx.z, 0.0)) + bentAt(p + vec2(dx.z, 0.0)));
  return sum;
}

float inkRow(vec2 p) {
  float most = bentAt(p).a;
  most = max(most, bentAt(p - vec2(uNear.x, 0.0)).a);
  most = max(most, bentAt(p - vec2(0.5 * uNear.x, 0.0)).a);
  most = max(most, bentAt(p + vec2(0.5 * uNear.x, 0.0)).a);
  most = max(most, bentAt(p + vec2(uNear.x, 0.0)).a);
  return most;
}

void main() {
  vec2 p = uOrigin + FlutterFragCoord().xy;

  vec3 dy = uOffsets * uTexel.y;
  vec4 soft = uWeights.x * wispRow(p);
  soft += uWeights.y * (wispRow(p - vec2(0.0, dy.x)) + wispRow(p + vec2(0.0, dy.x)));
  soft += uWeights.z * (wispRow(p - vec2(0.0, dy.y)) + wispRow(p + vec2(0.0, dy.y)));
  soft += uWeights.w * (wispRow(p - vec2(0.0, dy.z)) + wispRow(p + vec2(0.0, dy.z)));

  if (uGain <= 0.0) {
    fragColor = soft;
    return;
  }

  float near = inkRow(p);
  near = max(near, inkRow(p - vec2(0.0, uNear.y)));
  near = max(near, inkRow(p - vec2(0.0, 0.5 * uNear.y)));
  near = max(near, inkRow(p + vec2(0.0, 0.5 * uNear.y)));
  near = max(near, inkRow(p + vec2(0.0, uNear.y)));

  fragColor = soft * clamp(near * uGain, 0.0, 1.0);
}
