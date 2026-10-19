#version 460 core
// Het licht en de schaduw van een draaiende schijf (Saber, 19-10-2026: "de draaiende cd meer effect
// geven met schaduw, zo dat het realistisch wordt. Gebruik daarvoor shaders").
//
// Alles hier is ofwel rond (draait mee zonder te veranderen) ofwel aan het licht vast (staat stil
// terwijl de schijf draait, zoals de regenboog op een echte cd). Daarom wordt deze shader EEN keer
// gebakken tot een afbeelding (lib/ui/schijf_licht.dart) en per beeld alleen die afbeelding gelegd:
// onder Impeller is er geen rastergeheugen, en een shader in een vaste tekening zou anders elk beeld
// opnieuw rekenen. Als verf (Paint.shader) en niet als filter: zo werkt hij ook op de pc met Skia.
//
// Geen menging met wat eronder ligt (screen, zachtlicht): zo'n menging leest de draaiende schijf elk
// beeld terug. Gewoon doorzichtig erover, zoals CdGlans al deed (Shield, 18-10-2026).
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;  // grootte van het vlak in pixels
uniform vec4 uP;     // x: soort (0 cd, 1 vinyl, 2 echte scan), y: straal van het etiket (deel van de
                     // straal), z: donker thema (0 of 1), w: laag (0 licht op de schijf, 1 grondschaduw)
uniform vec4 uL;     // x, y: richting NAAR het licht (lengte 1, y omlaag), z: deel van het vlak dat de
                     // schijf is (straal / halve breedte), w: reserve

out vec4 fragColor;

vec3 regenboog(float h) {
  // Een zachte regenboog uit drie golven; h van 0 tot 1.
  vec3 k = clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
  return mix(vec3(1.0), k, 0.78);
}

// Kleur [kleur] met dekking [a] over [onder] (niet voorvermenigvuldigd).
vec4 over(vec4 onder, vec3 kleur, float a) {
  float oa = a + onder.a * (1.0 - a);
  vec3 rgb = oa > 0.0 ? (kleur * a + onder.rgb * onder.a * (1.0 - a)) / oa : vec3(0.0);
  return vec4(rgb, oa);
}

// Hoe ver hoek a van hoek b ligt, tussen 0 en pi.
float hoekAfstand(float a, float b) {
  float d = abs(a - b);
  d = mod(d, 6.2831853);
  return d > 3.1415927 ? 6.2831853 - d : d;
}

void main() {
  vec2 f = FlutterFragCoord().xy;
  vec2 c = uSize * 0.5;
  float halve = min(uSize.x, uSize.y) * 0.5;
  float straal = halve * uL.z;
  vec2 l = normalize(uL.xy);
  float donker = uP.z;
  float px = 1.0 / straal;  // een pixel, als deel van de straal

  if (uP.w > 0.5) {
    // De grondschaduw: een zachte schijf, iets van het licht af geschoven. Ligt onder de schijf; wat
    // je ziet is de halve maan rechtsonder.
    vec2 q = (f - c) / straal + l * 0.07;
    float r = length(q);
    float a = (1.0 - smoothstep(0.86, 1.16, r)) * mix(0.30, 0.50, donker);
    fragColor = vec4(0.0, 0.0, 0.0, 1.0) * a;
    return;
  }

  vec2 p = (f - c) / straal;
  float r = length(p);
  float binnen = 1.0 - smoothstep(1.0 - px, 1.0 + px, r);
  if (binnen <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec2 n = r > 0.0001 ? p / r : vec2(0.0, -1.0);
  float naarLicht = dot(n, l);  // 1 aan de kant van het licht, -1 aan de andere
  float etiket = uP.y;
  float soort = uP.x;

  vec4 uit = vec4(0.0);
  // Schaduw van de schijf op zichzelf: de kant van het licht af wordt naar de rand toe donkerder, zoals
  // een schijf met dikte die schuin licht krijgt.
  float zelf = smoothstep(0.55, 1.0, r) * max(-naarLicht, 0.0) * mix(0.16, 0.24, donker);
  uit = over(uit, vec3(0.0), zelf);

  if (soort < 1.5) {
    // De rand: een smalle heldere lijn aan de kant van het licht (de dikte die licht vangt).
    float rand = smoothstep(0.955 - px, 0.985, r) * (1.0 - smoothstep(0.995, 1.0 + px, r));
    float randLicht = rand * (0.18 + 0.55 * max(naarLicht, 0.0));
    uit = over(uit, vec3(1.0), randLicht);
  }

  if (soort < 0.5) {
    // Een cd. Het spoorvlak: tussen het etiket en de doorzichtige rand.
    float vlak = smoothstep(etiket + 0.015, etiket + 0.04, r) * (1.0 - smoothstep(0.94, 0.96, r));
    float hoek = atan(p.y, p.x);
    float lichtHoek = atan(l.y, l.x);
    // De regenboog: twee wiggen, op de lijn door het licht, en de kleur verloopt met de straal — zo breekt
    // licht in de sporen. Hij staat stil terwijl de schijf draait.
    float w1 = exp(-pow(hoekAfstand(hoek, lichtHoek) / 0.26, 2.0));
    float w2 = exp(-pow(hoekAfstand(hoek, lichtHoek + 3.1415927) / 0.30, 2.0)) * 0.75;
    vec3 k1 = regenboog(r * 2.3 + 0.05);
    vec3 k2 = regenboog(r * 2.3 + 0.55);
    float a1 = w1 * vlak * 0.34;
    float a2 = w2 * vlak * 0.30;
    uit = over(uit, k1, a1);
    uit = over(uit, k2, a2);
    // Een lichtveeg dwars op het licht, een stukje naar het licht toe: de glans van het plastic.
    vec2 dwars = vec2(-l.y, l.x);
    float veeg = exp(-pow((dot(p, l) - 0.28) / 0.07, 2.0)) * (1.0 - smoothstep(0.5, 0.95, abs(dot(p, dwars))));
    float av = veeg * vlak * 0.28;
    uit = over(uit, vec3(1.0), av);
    // De naaf: een doorzichtige stapelring rond het gat, licht aan de kant van de lamp.
    float naaf = exp(-pow((r - 0.115) / 0.012, 2.0)) * (0.20 + 0.35 * max(naarLicht, 0.0));
    uit = over(uit, vec3(1.0), naaf);
  } else if (soort < 1.5) {
    // Vinyl: twee zachte wiggen licht in de groeven, op de lijn door het licht, en een glans op het etiket.
    float groef = smoothstep(etiket + 0.015, etiket + 0.04, r) * (1.0 - smoothstep(0.975, 0.99, r));
    float hoek = atan(p.y, p.x);
    float lichtHoek = atan(l.y, l.x);
    float g1 = exp(-pow(hoekAfstand(hoek, lichtHoek) / 0.20, 2.0));
    float g2 = exp(-pow(hoekAfstand(hoek, lichtHoek + 3.1415927) / 0.24, 2.0)) * 0.7;
    float ag = (g1 + g2) * groef * 0.17;
    uit = over(uit, vec3(1.0), ag);
    float plak = (1.0 - smoothstep(etiket - 0.01, etiket + px, r)) * smoothstep(-0.2, 1.0, dot(p / max(etiket, 0.01), l));
    float ae = plak * 0.12;
    uit = over(uit, vec3(1.0), ae);
  }

  // Voorvermenigvuldigd, zoals Flutter het verwacht.
  fragColor = vec4(uit.rgb * uit.a, uit.a) * binnen;
}
