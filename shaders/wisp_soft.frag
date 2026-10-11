#version 460 core

// The soft half of a smoke, read off what is already drawn behind its strip (a backdrop filter whose input the
// engine has blurred first: `ImageFilter.compose` of this program over a blur). MEASURING ONLY so far
// (GHOST_PERF_SMOKE=through+soft). What is behind has the page's paper in it, so the ink's share of a blurred pixel
// is taken from how far it stands from the paper, against how far the page's ink stands from it: right for ink on
// flat paper, near enough over anything else. "near" (a dilate of the bent view's ink in shaders/wisp_haze.frag) is
// taken from that same share, there being one input: softer at its edge than the dilate.

#include <flutter/runtime_effect.glsl>

precision highp float;

// Set by the engine: the size of the blurred backdrop, in its own pixels.
uniform vec2 uSize;
// The view's corner on the screen, in the view's pixels, and the screen's pixels to one of them.
uniform vec2 uViewAt;
uniform float uRatio;
uniform vec4 uBand;
uniform vec2 uBandOn;
uniform vec4 uFade;
// The page's paper, how far its ink stands from it at most in a channel, and what the ink's share is multiplied
// by to say how near ink is.
uniform vec3 uPaper;
uniform float uContrast;
uniform float uGain;

uniform sampler2D uBlurred;

out vec4 fragColor;

float wispRamp(float x) {
  float t = 1.0 / (1.0 + 0.3275911 * abs(x) * 0.70710678);
  float y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-0.5 * x * x);
  return 0.5 * (1.0 + sign(x) * y);
}

float wispBand(vec2 p) {
  float along = mix(p.y, p.x, uBand.w);
  float sigma = max(uBand.z, 0.0001);
  float band = uBandOn.x * wispRamp((uBand.x - along) / sigma) + uBandOn.y * wispRamp((along - uBand.y) / sigma);
  return clamp(band, 0.0, 1.0);
}

float wispFade(vec2 p) {
  float along = mix(p.y, p.x, uBand.w);
  float rise = uFade.y > uFade.x ? clamp((along - uFade.x) / (uFade.y - uFade.x), 0.0, 1.0) : step(uFade.x, along);
  float fall = uFade.w > uFade.z ? clamp((uFade.w - along) / (uFade.w - uFade.z), 0.0, 1.0) : 1.0 - step(uFade.w, along);
  return rise * fall;
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec2 p = px / uRatio - uViewAt;
  vec3 away = texture(uBlurred, px / uSize).rgb - uPaper;
  float share = clamp(max(abs(away.r), max(abs(away.g), abs(away.b))) / max(uContrast, 0.001), 0.0, 1.0);
  // The blurred ink alone, its colour multiplied by its share: what is left when the paper's part is taken away.
  // A block of colour nearer the paper than the ink is counts as part ink, and comes out a little lighter and
  // less softened than the pictures make it.
  vec3 ink = away + uPaper * share;
  float shown = clamp(share * uGain, 0.0, 1.0) * wispBand(p) * wispFade(p);
  fragColor = vec4(ink, share) * shown;
}
