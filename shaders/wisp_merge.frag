#version 460 core

// The wisp's last step: the second half of every smoke filter the web app writes (art/WispEdgeFilter.tsx from
// `bandAlpha` to the closing `feMerge`; art/wispBox.ts `smokeFrom`). Three pictures come in - the view as it is, the
// view bent (shaders/wisp_bend.frag) and the bent view blurred - and one goes out: the view itself where the band is
// not, the bent view in the band, and over that the blur kept to within a little of the bent strokes, so it softens
// the letters and never glows into the empty paper beside them. Then the view's own fade, which the page lays on as
// a `mask-image` after its filter.

#include <flutter/runtime_effect.glsl>

precision highp float;

// The drawn rectangle's corner in the view's own pixels.
uniform vec2 uOrigin;
// Where uSource lies in the view: left, top, width, height.
uniform vec4 uSourceRect;
// Where uBent and uSoft lie in the view.
uniform vec4 uBentRect;
// The band, as wisp_bend.frag has it: lip A, lip B, sigma, axis.
uniform vec4 uBand;
uniform vec2 uBandOn;
// `feMorphology` dilate's radius, across and down.
uniform vec2 uNear;
// The mask along the band's axis: clear up to x, whole from y, whole until z, clear from w.
uniform vec4 uFade;

uniform sampler2D uSource;
uniform sampler2D uBent;
uniform sampler2D uSoft;

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

// Where a point of the view falls in a picture laid over `rect` of it, or outside 0 to 1 where it does not.
vec2 inRect(vec4 rect, vec2 p) {
  return (p - rect.xy) / rect.zw;
}

bool outside(vec2 uv) {
  return uv.x < 0.0 || uv.y < 0.0 || uv.x >= 1.0 || uv.y >= 1.0;
}

// A picture the engine made (toImageSync) is sampled the right way up on every backend: flipping it for OpenGL ES,
// as Flutter's notes on fragment shaders say to, drew each strip upside down on Impeller's OpenGL ES (seen on the
// Android emulator, 2026-10-07). Vulkan was never flipped.
vec4 sourceAt(vec2 p) {
  vec2 uv = inRect(uSourceRect, p);
  if (outside(uv)) {
    return vec4(0.0);
  }
  return texture(uSource, uv);
}

vec4 bentAt(vec2 p) {
  vec2 uv = inRect(uBentRect, p);
  if (outside(uv)) {
    return vec4(0.0);
  }
  return texture(uBent, uv);
}

vec4 softAt(vec2 p) {
  vec2 uv = inRect(uBentRect, p);
  if (outside(uv)) {
    return vec4(0.0);
  }
  return texture(uSoft, uv);
}

float bentAlpha(vec2 p, float dx, float dy) {
  return bentAt(p + vec2(dx, dy) * uNear).a;
}

// How much ink the bent view has within the dilate's box of a point: `near`'s alpha. The box is read on a grid of
// seven by seven, each tap the mean of the pixels round it, so no stroke a pixel wide falls between two of them.
float wispNear(vec2 p) {
  float most = 0.0;
  for (int i = 0; i < 7; i++) {
    float dx = float(i) / 3.0 - 1.0;
    most = max(most, bentAlpha(p, dx, -1.0));
    most = max(most, bentAlpha(p, dx, -2.0 / 3.0));
    most = max(most, bentAlpha(p, dx, -1.0 / 3.0));
    most = max(most, bentAlpha(p, dx, 0.0));
    most = max(most, bentAlpha(p, dx, 1.0 / 3.0));
    most = max(most, bentAlpha(p, dx, 2.0 / 3.0));
    most = max(most, bentAlpha(p, dx, 1.0));
  }
  return most;
}

// A `linear-gradient` mask along the axis: transparent, black, black, transparent at the four stops.
float wispFade(vec2 p) {
  float along = mix(p.y, p.x, uBand.w);
  float rise = uFade.y > uFade.x ? clamp((along - uFade.x) / (uFade.y - uFade.x), 0.0, 1.0) : step(uFade.x, along);
  float fall = uFade.w > uFade.z ? clamp((uFade.w - along) / (uFade.w - uFade.z), 0.0, 1.0) : 1.0 - step(uFade.w, along);
  return rise * fall;
}

void main() {
  vec2 p = uOrigin + FlutterFragCoord().xy;
  float band = wispBand(p);
  vec4 source = sourceAt(p);
  vec4 bent = bentAt(p);
  vec4 soft = softAt(p);

  // `rest`, `bentIn` and `smoke`, merged one over the next.
  vec4 rest = source * (1.0 - band);
  vec4 bentIn = bent * band;
  vec4 smoke = soft * (wispNear(p) * band);
  vec4 color = bentIn + rest * (1.0 - bentIn.a);
  color = smoke + color * (1.0 - smoke.a);

  fragColor = color * wispFade(p);
}
