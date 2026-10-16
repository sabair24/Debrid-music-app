#version 460 core
// De lensrand van vloeibaar glas (16-10-2026): de achtergrond buigt aan de rand van een afgeronde
// rechthoek, met een lichtrand linksboven. Alleen onder Impeller (zie lib/ui/glas.dart).
//
// Wat de engine doet (nagelezen in de bron van Flutter 3.41.9):
//  - uSize (de eerste vec2) wordt overschreven met de grootte van de invoertextuur: de hele pass.
//  - FlutterFragCoord() is een pixel in die textuur, y omlaag op elke backend.
//  - de invoer (uTex) wordt NEAREST gesampeld, dus de rand sampelt zelf bilineair.
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;  // engine: grootte van de invoer, in pixels
uniform vec4 uRect;  // x, y, breedte, hoogte van het glas, in pixels van de pass
uniform vec4 uP;     // hoekstraal, breedte van de rand, verschuiving, sterkte van de lichtrand
uniform sampler2D uTex;

out vec4 fragColor;

float sdRR(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// De normaal naar buiten, ook langs de rechte zijden (daar wijst hij loodrecht weg).
vec2 nRR(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  vec2 s = vec2(p.x < 0.0 ? -1.0 : 1.0, p.y < 0.0 ? -1.0 : 1.0);
  vec2 n;
  if (q.x > 0.0 && q.y > 0.0) {
    n = normalize(q);
  } else if (q.x > q.y) {
    n = vec2(1.0, 0.0);
  } else {
    n = vec2(0.0, 1.0);
  }
  return s * n;
}

vec4 lees(vec2 px) {
  vec2 uv = px / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(uTex, uv);
}

// Vier keer lezen en mengen: de invoer geeft alleen hele pixels terug, en een rand die op een halve
// pixel verschuift krijgt anders trapjes.
vec4 leesVloeiend(vec2 px) {
  vec2 f = px - 0.5;
  vec2 i = floor(f);
  vec2 t = f - i;
  vec4 a = lees(i + vec2(0.5, 0.5));
  vec4 b = lees(i + vec2(1.5, 0.5));
  vec4 c = lees(i + vec2(0.5, 1.5));
  vec4 d = lees(i + vec2(1.5, 1.5));
  return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
}

void main() {
  vec2 f = FlutterFragCoord().xy;
  vec2 b = uRect.zw * 0.5;
  vec2 p = f - (uRect.xy + b);
  float r = min(uP.x, min(b.x, b.y));
  float sd = sdRR(p, b, r);
  // Buiten het glas: niets, zodat de achtergrond gewoon blijft staan.
  float alfa = 1.0 - smoothstep(-1.0, 0.0, sd);
  if (alfa <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec2 n = nRR(p, b, r);
  // 1 op de rand, 0 dieper dan de randbreedte; een kwartcirkel als profiel.
  float x = 1.0 - clamp(-sd / max(uP.y, 1.0), 0.0, 1.0);
  float buiging = 1.0 - sqrt(max(1.0 - x * x, 0.0));
  vec4 kleur = leesVloeiend(f - n * uP.z * buiging);
  // Het licht valt van linksboven: daar een smalle heldere rand, rechtsonder nauwelijks.
  float licht = pow(x, 6.0) * max(dot(n, vec2(-0.7071, -0.7071)), 0.0) * uP.w;
  fragColor = vec4(min(kleur.rgb + licht, vec3(1.0)), 1.0) * alfa;
}
