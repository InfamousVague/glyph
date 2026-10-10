#version 460 core

// The wisp in one pass over the screen: the bend (shaders/wisp_bend.frag) and the merge (shaders/wisp_merge.frag)
// of every smoke filter the web app writes, worked out together for each pixel of a strip.
//
// The three-pass drawing made two pictures the size of the strip on every frame (the view bent, and that blurred)
// and then read the bent one forty-nine times a pixel to find the ink near it. Here the bent view is not a picture:
// a pixel reads the view where the noise throws it. The noise comes in as a picture of its own, made when the
// smoke last moved (shaders/wisp_field.frag), and what is soft in the smoke - the blur of the bent view, kept to
// within a little of its strokes - comes in already made, small (shaders/wisp_haze.frag), and is read once.

#include <flutter/runtime_effect.glsl>

precision highp float;

// The drawn rectangle's corner in the view's own pixels: a fragment is at uOrigin + FlutterFragCoord().
uniform vec2 uOrigin;
// Where uSource lies in the view: left, top, width, height. Outside it the source is clear, as SourceGraphic is.
uniform vec4 uSourceRect;
// Where the bent view is worked out at all, the filter's own subregion: left, top, width, height. Clear outside it.
uniform vec4 uBentRect;
// Where uHaze lies in the view.
uniform vec4 uHazeRect;
// Where uField lies in the view, and how many pixels it has across and down.
uniform vec4 uFieldRect;
uniform vec2 uFieldSize;
// The band: lip A (white before it), lip B (white after it), the ramp's sigma, and the axis the lips lie along.
uniform vec4 uBand;
uniform vec2 uBandOn;
// `scale` on the displacement.
uniform float uBend;
// The mask along the band's axis: clear up to x, whole from y, whole until z, clear from w.
uniform vec4 uFade;

uniform sampler2D uSource;
uniform sampler2D uField;
uniform sampler2D uHaze;

out vec4 fragColor;

// The noise at one pixel of its picture (shaders/wisp_field.frag): twelve bits an axis, unpacked.
vec2 wispFieldPixel(vec2 pixel) {
  vec2 uv = (clamp(pixel, vec2(0.0), uFieldSize - vec2(1.0)) + vec2(0.5)) / uFieldSize;
  vec3 t = floor(texture(uField, uv).rgb * 255.0 + 0.5);
  float high = floor(t.g / 16.0);
  float low = t.g - high * 16.0;
  return vec2(t.r * 16.0 + high, low * 256.0 + t.b) / 4095.0;
}

// The noise at a point of the view: the four pixels of its picture round the point, weighed by where it lies
// between them. Unpacked first and weighed after; the engine's own reading between pixels would weigh the packed
// bytes, which mean nothing apart.
vec2 wispField(vec2 p) {
  vec2 at = (p - uFieldRect.xy) / uFieldRect.zw * uFieldSize - vec2(0.5);
  vec2 corner = floor(at);
  vec2 f = at - corner;
  vec2 upper = mix(wispFieldPixel(corner), wispFieldPixel(corner + vec2(1.0, 0.0)), f.x);
  vec2 lower = mix(wispFieldPixel(corner + vec2(0.0, 1.0)), wispFieldPixel(corner + vec2(1.0, 1.0)), f.x);
  return mix(upper, lower, f.y);
}

// The normal distribution's running total: what a step looks like after `feGaussianBlur`.
float wispRamp(float x) {
  float t = 1.0 / (1.0 + 0.3275911 * abs(x) * 0.70710678);
  float y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-0.5 * x * x);
  return 0.5 * (1.0 + sign(x) * y);
}

// The band at a point, 0 to 1: the white strips on black, blurred along their axis.
float wispBand(vec2 p) {
  float along = mix(p.y, p.x, uBand.w);
  float sigma = max(uBand.z, 0.0001);
  float band = uBandOn.x * wispRamp((uBand.x - along) / sigma) + uBandOn.y * wispRamp((along - uBand.y) / sigma);
  return clamp(band, 0.0, 1.0);
}

bool outside(vec2 uv) {
  return uv.x < 0.0 || uv.y < 0.0 || uv.x >= 1.0 || uv.y >= 1.0;
}

// A picture the engine made (toImageSync) is sampled the right way up on every backend (shaders/wisp_merge.frag).
vec4 sourceAt(vec2 p) {
  vec2 uv = (p - uSourceRect.xy) / uSourceRect.zw;
  if (outside(uv)) {
    return vec4(0.0);
  }
  return texture(uSource, uv);
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

  // `bent`: the view read where the noise throws this pixel, inside the filter's subregion and clear outside it.
  vec4 bent = vec4(0.0);
  if (!outside((p - uBentRect.xy) / uBentRect.zw)) {
    bent = sourceAt(p + uBend * band * (wispField(p) - vec2(0.5)));
  }

  // `soft` kept to `near`, made small and read between its pixels.
  vec4 haze = vec4(0.0);
  vec2 hazeUv = (p - uHazeRect.xy) / uHazeRect.zw;
  if (!outside(hazeUv)) {
    haze = texture(uHaze, hazeUv);
  }

  // `rest`, `bentIn` and `smoke`, merged one over the next.
  vec4 rest = source * (1.0 - band);
  vec4 bentIn = bent * band;
  vec4 smoke = haze * band;
  vec4 color = bentIn + rest * (1.0 - bentIn.a);
  color = smoke + color * (1.0 - smoke.a);

  fragColor = color * wispFade(p);
}
