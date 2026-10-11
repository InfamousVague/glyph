#version 460 core

// The wisp's bend, drawn small: shaders/wisp_bend.frag, for the picture a smoke's blur is made from
// (shaders/wisp_haze.frag), which is a half or a quarter of the screen's size each way. The noise, the band and the
// throw are that file's, line for line; what differs is how the view is read where a point is thrown to: at four
// points a quarter of this picture's own pixel out, each between four of the view's, so every pixel of the view
// under one of this picture's is counted once. A small picture that read the view at one point would take one
// pixel in four or sixteen and leave the rest, and thin strokes would come and go as they scrolled.
//
// A file of its own, and not a switch in wisp_bend.frag: that file draws every letter in smoke and the first
// drawing of every strip, and its pictures are held pixel for pixel. Changing a line of it changes how its
// arithmetic is compiled, and a pixel thrown to the very edge of another lands the other side.

#include <flutter/runtime_effect.glsl>

precision highp float;

// The drawn rectangle's corner in the view's own pixels: a fragment is at uOrigin + FlutterFragCoord().
uniform vec2 uOrigin;
// Where uSource lies in the view: left, top, width, height. Outside it the source is clear, as SourceGraphic is.
uniform vec4 uSourceRect;
// `baseFrequency`, per pixel.
uniform vec2 uFrequency;
// `feOffset` on the noise: the drift's slide.
uniform vec2 uSlide;
// The turbulence's own subregion: left, top, right, bottom. Slid out of it, the noise is black.
uniform vec4 uNoiseRect;
// The band the bend follows: lip A (white before it), lip B (white after it), the ramp's sigma, and the axis the
// lips lie along (0 down the view, 1 across it).
uniform vec4 uBand;
// Which of the two lips are there.
uniform vec2 uBandOn;
// `scale` on the displacement.
uniform float uBend;
// How far round the point it is thrown to the view is read, across and down: a quarter of this picture's pixel.
uniform vec2 uSpread;

uniform sampler2D uSource;
uniform sampler2D uTable;

out vec4 fragColor;

// The gradient the lattice gives a cell for a channel: twelve bits an axis, packed in an opaque texel.
vec2 wispGradient(float channel, vec2 cell) {
  vec2 at = mod(cell, 256.0);
  vec2 uv = vec2((channel * 256.0 + at.x + 0.5) / 512.0, (at.y + 0.5) / 256.0);
  vec3 t = floor(texture(uTable, uv).rgb * 255.0 + 0.5);
  float high = floor(t.g / 16.0);
  float low = t.g - high * 16.0;
  return vec2(t.r * 16.0 + high, low * 256.0 + t.b) / 4095.0 * 2.0 - 1.0;
}

// `noise2` of the specification: one octave at the noise's own coordinates.
float wispNoise(float channel, vec2 v) {
  vec2 cell = floor(v);
  vec2 r = v - cell;
  vec2 s = r * r * (3.0 - 2.0 * r);
  float u = dot(r, wispGradient(channel, cell));
  float w = dot(r - vec2(1.0, 0.0), wispGradient(channel, cell + vec2(1.0, 0.0)));
  float a = mix(u, w, s.x);
  u = dot(r - vec2(0.0, 1.0), wispGradient(channel, cell + vec2(0.0, 1.0)));
  w = dot(r - vec2(1.0, 1.0), wispGradient(channel, cell + vec2(1.0, 1.0)));
  float b = mix(u, w, s.x);
  return mix(a, b, s.y);
}

// Red and green of `fractalNoise` with two octaves, as colours from 0 to 1.
vec2 wispField(vec2 point) {
  vec2 v = point * uFrequency;
  vec2 sum = vec2(wispNoise(0.0, v), wispNoise(1.0, v));
  v *= 2.0;
  sum += 0.5 * vec2(wispNoise(0.0, v), wispNoise(1.0, v));
  return clamp(sum * 0.5 + 0.5, 0.0, 1.0);
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

vec4 wispSource(vec2 p) {
  vec2 uv = (p - uSourceRect.xy) / uSourceRect.zw;
  if (uv.x < 0.0 || uv.y < 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
    return vec4(0.0);
  }
  return texture(uSource, uv);
}

void main() {
  vec2 p = uOrigin + FlutterFragCoord().xy;
  // Chromium works the noise out half a pixel on from the pixel's own middle.
  vec2 q = p - uSlide;
  vec2 noise = vec2(0.0);
  if (q.x >= uNoiseRect.x && q.y >= uNoiseRect.y && q.x < uNoiseRect.z && q.y < uNoiseRect.w) {
    noise = wispField(q + vec2(0.5));
  }
  // `field`: neutral grey where the band is not, the noise where it is whole.
  vec2 at = p + uBend * wispBand(p) * (noise - vec2(0.5));
  fragColor = 0.25 * (wispSource(at - uSpread) + wispSource(at + vec2(uSpread.x, -uSpread.y)) + wispSource(at + vec2(-uSpread.x, uSpread.y)) + wispSource(at + uSpread));
}
