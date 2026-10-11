#version 460 core

// A view's wisps drawn as the view itself is: the view's layers go through this program once, as an image filter
// over them (Impeller: `ImageFilter.shader`), and it bends and fades the two strips the smoke stands in and passes
// the rest as it came. MEASURING ONLY so far (GHOST_PERF_SMOKE=through): the bend of shaders/wisp_smoke.frag and
// the view's fade, clear kept clear, with no picture of the view asked for and none made small for the soft half,
// which is not drawn at all here. It is here to say what a page's smoke costs a frame when nothing is drawn twice
// and nothing behind the view is read, before the look is brought to it.

#include <flutter/runtime_effect.glsl>

precision highp float;

// Set by the engine: the size of the view's picture, in its own pixels.
uniform vec2 uSize;
// The point of the view that picture's first pixel is of, in the view's own pixels, and the picture's pixels to one
// of them. The picture is of what of the view is seen, which is not all of it where the screen or a clip cuts it.
uniform vec2 uViewAt;
uniform float uRatio;
uniform vec4 uFieldRect;
uniform vec2 uFieldSize;
uniform vec4 uFade;
uniform float uAxis;
// Two smokes, each over its own strip of the view (left, top, right, bottom; an empty one is no smoke).
uniform vec4 uStripA;
uniform vec2 uFrequencyA;
uniform vec2 uSlideA;
uniform vec4 uNoiseRectA;
uniform vec4 uBandA;
uniform vec2 uBandOnA;
uniform float uBendA;
uniform vec4 uStripB;
uniform vec2 uFrequencyB;
uniform vec2 uSlideB;
uniform vec4 uNoiseRectB;
uniform vec4 uBandB;
uniform vec2 uBandOnB;
uniform float uBendB;
// Measuring only: 3 draws the first smoke's band in red and its noise in green and blue, 4 the pixel's place in the
// view as the program has it (a stripe every hundred pixels down in red and across in green) and in blue whether
// it is in a strip.
uniform float uProbe;

// Set by the engine: the view.
uniform sampler2D uSource;
uniform sampler2D uField;

out vec4 fragColor;

// The noise at one pixel of its picture: twelve bits an axis, packed in three bytes (shaders/wisp_field.frag).
vec2 wispFieldPixel(vec2 pixel) {
  vec2 uv = (clamp(pixel, vec2(0.0), uFieldSize - vec2(1.0)) + vec2(0.5)) / uFieldSize;
  vec3 t = floor(texture(uField, uv).rgb * 255.0 + 0.5);
  float high = floor(t.g / 16.0);
  float low = t.g - high * 16.0;
  return vec2(t.r * 16.0 + high, low * 256.0 + t.b) / 4095.0;
}

// The noise at a point of its own space: the four pixels of its picture round the point, unpacked and then weighed.
vec2 wispField(vec2 v) {
  vec2 at = (v - uFieldRect.xy) / uFieldRect.zw * uFieldSize - vec2(0.5);
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

float wispBand(vec2 p, vec4 lips, vec2 on) {
  float along = mix(p.y, p.x, uAxis);
  float sigma = max(lips.z, 0.0001);
  float band = on.x * wispRamp((lips.x - along) / sigma) + on.y * wispRamp((along - lips.y) / sigma);
  return clamp(band, 0.0, 1.0);
}

float wispFade(vec2 p) {
  float along = mix(p.y, p.x, uAxis);
  float rise = uFade.y > uFade.x ? clamp((along - uFade.x) / (uFade.y - uFade.x), 0.0, 1.0) : step(uFade.x, along);
  float fall = uFade.w > uFade.z ? clamp((uFade.w - along) / (uFade.w - uFade.z), 0.0, 1.0) : 1.0 - step(uFade.w, along);
  return rise * fall;
}

// The view at a point of its own, clear outside its picture.
vec4 viewAt(vec2 p) {
  vec2 uv = (p - uViewAt) * uRatio / uSize;
  if (uv.x < 0.0 || uv.y < 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
    return vec4(0.0);
  }
  return texture(uSource, uv);
}

vec4 wispSmoke(vec2 p, vec4 source, vec2 frequency, vec2 slide, vec4 noiseRect, vec4 lips, vec2 on, float bend) {
  float band = wispBand(p, lips, on);
  vec2 q = p - slide;
  vec2 noise = vec2(0.0);
  if (q.x >= noiseRect.x && q.y >= noiseRect.y && q.x < noiseRect.z && q.y < noiseRect.w) {
    noise = wispField((q + vec2(0.5)) * frequency);
  }
  vec4 bentIn = viewAt(p + bend * band * (noise - vec2(0.5))) * band;
  vec4 rest = source * (1.0 - band);
  return (bentIn + rest * (1.0 - bentIn.a)) * wispFade(p);
}

bool within(vec2 p, vec4 strip) {
  return p.x >= strip.x && p.y >= strip.y && p.x < strip.z && p.y < strip.w;
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec2 p = uViewAt + px / uRatio;
  vec4 color = texture(uSource, px / uSize);
  if (within(p, uStripA)) {
    color = wispSmoke(p, color, uFrequencyA, uSlideA, uNoiseRectA, uBandA, uBandOnA, uBendA);
  } else if (within(p, uStripB)) {
    color = wispSmoke(p, color, uFrequencyB, uSlideB, uNoiseRectB, uBandB, uBandOnB, uBendB);
  }
  fragColor = color;
  if (uProbe > 3.5) {
    fragColor = vec4(fract(p.y / 100.0), fract(p.x / 100.0), within(p, uStripA) ? 1.0 : (within(p, uStripB) ? 0.5 : 0.0), 1.0);
  } else if (uProbe > 2.5) {
    vec2 q = p - uSlideA;
    fragColor = vec4(wispBand(p, uBandA, uBandOnA), wispField((q + vec2(0.5)) * uFrequencyA), 1.0);
  }
}
