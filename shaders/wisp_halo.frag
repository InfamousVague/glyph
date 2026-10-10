#version 460 core

// The halo round the home page's dock, in one pass (art/dockSmoke.ts, home/HomeScreen.module.css `.dockHalo`): what
// scrolls behind the dock bent and softened, washed toward the page's paper, and shown through the halo's mask - a
// soft core at the pill, added to a wider ramp cut by a tile of smoke that slides with the page's drift.
//
// Drawn as the stylesheet composes it, the halo was a layer for the backdrop, a layer for the mask and a layer for
// the ramp under its tile, each a picture the engine made on every frame beside the bent view and its blur. Here
// the two pills come in as one small picture made once for the dock's size (the ramp in red, the core in green),
// the tile is read where it has slid to, and the softened view comes in small (shaders/wisp_haze.frag).

#include <flutter/runtime_effect.glsl>

precision highp float;

// The drawn rectangle's corner in the view's own pixels.
uniform vec2 uOrigin;
// Where uSource lies in the view: left, top, width, height.
uniform vec4 uSourceRect;
// Where uSoft lies in the view.
uniform vec4 uSoftRect;
// The halo's own box, which uPills lies over and the tile is laid from.
uniform vec4 uHaloRect;
// The page's ground at the wash's strength, its colour multiplied by its alpha.
uniform vec4 uWash;
// How far the tile has slid, and its side.
uniform vec2 uSlide;
uniform float uTileSide;

uniform sampler2D uSource;
uniform sampler2D uSoft;
uniform sampler2D uPills;
uniform sampler2D uTile;

out vec4 fragColor;

void main() {
  vec2 p = uOrigin + FlutterFragCoord().xy;

  vec2 uv = (p - uSourceRect.xy) / uSourceRect.zw;
  vec4 view = vec4(0.0);
  if (uv.x >= 0.0 && uv.y >= 0.0 && uv.x < 1.0 && uv.y < 1.0) {
    view = texture(uSource, uv);
  }

  // The backdrop through its filter, under the wash.
  vec4 soft = texture(uSoft, clamp((p - uSoftRect.xy) / uSoftRect.zw, 0.0, 1.0));
  vec4 washed = uWash + soft * (1.0 - uWash.a);

  // The mask: the core, added to the ramp where the tile is.
  vec2 at = (p - uHaloRect.xy) / uHaloRect.zw;
  float mask = 0.0;
  if (at.x >= 0.0 && at.y >= 0.0 && at.x < 1.0 && at.y < 1.0) {
    vec4 pills = texture(uPills, at);
    float tile = texture(uTile, fract((p - uHaloRect.xy - uSlide) / uTileSide)).a;
    float torn = pills.r * tile;
    mask = pills.g + torn * (1.0 - pills.g);
  }

  fragColor = washed * mask + view * (1.0 - washed.a * mask);
}
