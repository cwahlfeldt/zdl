#include <metal_stdlib>
using namespace metal;

// MIT License
// Copyright (c) 2013 Inigo Quilez
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

constant float PI = 3.14159265359;
constant uint MAX_POINT_LIGHTS = 16;
constant uint MAX_SPOT_LIGHTS = 8;

struct Vertex3DInput {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
    float4 color [[attribute(3)]];
};

struct Vertex3DOutput {
    float4 position [[position]];
    float3 world_pos;
};

struct Uniforms {
    float4x4 model;
    float4x4 view;
    float4x4 projection;
};

struct PointLight {
    float4 position_range;
    float4 color_intensity;
};

struct SpotLight {
    float4 position_range;
    float4 direction_outer;
    float4 color_intensity;
    float4 inner_pad;
};

struct LightUniforms {
    float4 directional_direction;
    float4 directional_color_intensity;
    float4 ambient_color_intensity;
    float4 camera_position;
    float4 ibl_params; // x=env_intensity, y=max_lod, z=use_ibl, w=spec_intensity
    uint point_light_count;
    uint spot_light_count;
    uint _pad[2];
    PointLight point_lights[MAX_POINT_LIGHTS];
    SpotLight spot_lights[MAX_SPOT_LIGHTS];
};

#define ZERO 0

// =============================================================================
// Vertex Shader
// =============================================================================

vertex Vertex3DOutput raymarch_vertex_main(
    Vertex3DInput in [[stage_in]],
    constant Uniforms& uniforms [[buffer(0)]]
) {
    Vertex3DOutput out;
    float4 world_pos = uniforms.model * float4(in.position, 1.0);
    out.world_pos = world_pos.xyz;
    out.position = uniforms.projection * uniforms.view * world_pos;
    return out;
}

// =============================================================================
// Raymarching SDFs
// =============================================================================

float sgn(float v) {
    return (v > 0.0) ? 1.0 : ((v < 0.0) ? -1.0 : 0.0);
}

float dot2(float2 v) { return dot(v, v); }
float dot2(float3 v) { return dot(v, v); }
float ndot(float2 a, float2 b) { return a.x * b.x - a.y * b.y; }

float sdSphere(float3 p, float s) { return length(p) - s; }

float sdBox(float3 p, float3 b) {
    float3 d = abs(p) - b;
    return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0));
}

float sdBoxFrame(float3 p, float3 b, float e) {
    p = abs(p) - b;
    float3 q = abs(p + e) - e;

    return min(min(
        length(max(float3(p.x, q.y, q.z), 0.0)) + min(max(p.x, max(q.y, q.z)), 0.0),
        length(max(float3(q.x, p.y, q.z), 0.0)) + min(max(q.x, max(p.y, q.z)), 0.0)),
        length(max(float3(q.x, q.y, p.z), 0.0)) + min(max(q.x, max(q.y, p.z)), 0.0));
}

float sdEllipsoid(float3 p, float3 r) {
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

float sdTorus(float3 p, float2 t) {
    return length(float2(length(p.xz) - t.x, p.y)) - t.y;
}

float sdCappedTorus(float3 p, float2 sc, float ra, float rb) {
    p.x = abs(p.x);
    float k = (sc.y * p.x > sc.x * p.y) ? dot(p.xy, sc) : length(p.xy);
    return sqrt(dot(p, p) + ra * ra - 2.0 * ra * k) - rb;
}

float sdHexPrism(float3 p, float2 h) {
    const float3 k = float3(-0.8660254, 0.5, 0.57735);
    p = abs(p);
    p.xy -= 2.0 * min(dot(k.xy, p.xy), 0.0) * k.xy;
    float2 d = float2(
        length(p.xy - float2(clamp(p.x, -k.z * h.x, k.z * h.x), h.x)) * sgn(p.y - h.x),
        p.z - h.y);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

float sdOctogonPrism(float3 p, float r, float h) {
    const float3 k = float3(-0.9238795325, 0.3826834323, 0.4142135623);
    p = abs(p);
    p.xy -= 2.0 * min(dot(float2(k.x, k.y), p.xy), 0.0) * float2(k.x, k.y);
    p.xy -= 2.0 * min(dot(float2(-k.x, k.y), p.xy), 0.0) * float2(-k.x, k.y);
    p.xy -= float2(clamp(p.x, -k.z * r, k.z * r), r);
    float2 d = float2(length(p.xy) * sgn(p.y), p.z - h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

float sdCapsule(float3 p, float3 a, float3 b, float r) {
    float3 pa = p - a;
    float3 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

float sdRoundCone(float3 p, float r1, float r2, float h) {
    float2 q = float2(length(p.xz), p.y);

    float b = (r1 - r2) / h;
    float a = sqrt(1.0 - b * b);
    float k = dot(q, float2(-b, a));

    if (k < 0.0) return length(q) - r1;
    if (k > a * h) return length(q - float2(0.0, h)) - r2;

    return dot(q, float2(a, b)) - r1;
}

float sdRoundCone(float3 p, float3 a, float3 b, float r1, float r2) {
    float3 ba = b - a;
    float l2 = dot(ba, ba);
    float rr = r1 - r2;
    float a2 = l2 - rr * rr;
    float il2 = 1.0 / l2;

    float3 pa = p - a;
    float y = dot(pa, ba);
    float z = y - l2;
    float x2 = dot2(pa * l2 - ba * y);
    float y2 = y * y * l2;
    float z2 = z * z * l2;

    float k = sgn(rr) * rr * rr * x2;
    if (sgn(z) * a2 * z2 > k) return sqrt(x2 + z2) * il2 - r2;
    if (sgn(y) * a2 * y2 < k) return sqrt(x2 + y2) * il2 - r1;
    return (sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
}

float sdTriPrism(float3 p, float2 h) {
    const float k = sqrt(3.0);
    h.x *= 0.5 * k;
    p.xy /= h.x;
    p.x = abs(p.x) - 1.0;
    p.y = p.y + 1.0 / k;
    if (p.x + k * p.y > 0.0) p.xy = float2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
    p.x -= clamp(p.x, -2.0, 0.0);
    float d1 = length(p.xy) * sgn(-p.y) * h.x;
    float d2 = abs(p.z) - h.y;
    return length(max(float2(d1, d2), 0.0)) + min(max(d1, d2), 0.0);
}

float sdCylinder(float3 p, float2 h) {
    float2 d = abs(float2(length(p.xz), p.y)) - h;
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

float sdCylinder(float3 p, float3 a, float3 b, float r) {
    float3 pa = p - a;
    float3 ba = b - a;
    float baba = dot(ba, ba);
    float paba = dot(pa, ba);

    float x = length(pa * baba - ba * paba) - r * baba;
    float y = abs(paba - baba * 0.5) - baba * 0.5;
    float x2 = x * x;
    float y2 = y * y * baba;
    float d = (max(x, y) < 0.0) ? -min(x2, y2) : (((x > 0.0) ? x2 : 0.0) + ((y > 0.0) ? y2 : 0.0));
    return sgn(d) * sqrt(abs(d)) / baba;
}

float sdCone(float3 p, float2 c, float h) {
    float2 q = h * float2(c.x, -c.y) / c.y;
    float2 w = float2(length(p.xz), p.y);

    float2 a = w - q * clamp(dot(w, q) / dot(q, q), 0.0, 1.0);
    float2 b = w - q * float2(clamp(w.x / q.x, 0.0, 1.0), 1.0);
    float k = sgn(q.y);
    float d = min(dot(a, a), dot(b, b));
    float s = max(k * (w.x * q.y - w.y * q.x), k * (w.y - q.y));
    return sqrt(d) * sgn(s);
}

float sdCappedCone(float3 p, float h, float r1, float r2) {
    float2 q = float2(length(p.xz), p.y);

    float2 k1 = float2(r2, h);
    float2 k2 = float2(r2 - r1, 2.0 * h);
    float2 ca = float2(q.x - min(q.x, (q.y < 0.0) ? r1 : r2), abs(q.y) - h);
    float2 cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / dot2(k2), 0.0, 1.0);
    float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot2(ca), dot2(cb)));
}

float sdCappedCone(float3 p, float3 a, float3 b, float ra, float rb) {
    float rba = rb - ra;
    float baba = dot(b - a, b - a);
    float papa = dot(p - a, p - a);
    float paba = dot(p - a, b - a) / baba;

    float x = sqrt(papa - paba * paba * baba);

    float cax = max(0.0, x - ((paba < 0.5) ? ra : rb));
    float cay = abs(paba - 0.5) - 0.5;

    float k = rba * rba + baba;
    float f = clamp((rba * (x - ra) + paba * baba) / k, 0.0, 1.0);

    float cbx = x - ra - f * rba;
    float cby = paba - f;

    float s = (cbx < 0.0 && cay < 0.0) ? -1.0 : 1.0;

    return s * sqrt(min(cax * cax + cay * cay * baba, cbx * cbx + cby * cby * baba));
}

float sdSolidAngle(float3 pos, float2 c, float ra) {
    float2 p = float2(length(pos.xz), pos.y);
    float l = length(p) - ra;
    float m = length(p - c * clamp(dot(p, c), 0.0, ra));
    return max(l, m * sgn(c.y * p.x - c.x * p.y));
}

float sdOctahedron(float3 p, float s) {
    p = abs(p);
    float m = p.x + p.y + p.z - s;

    float3 q;
    if (3.0 * p.x < m) q = p.xyz;
    else if (3.0 * p.y < m) q = p.yzx;
    else if (3.0 * p.z < m) q = p.zxy;
    else return m * 0.57735027;
    float k = clamp(0.5 * (q.z - q.y + s), 0.0, s);
    return length(float3(q.x, q.y - s + k, q.z - k));
}

float sdPyramid(float3 p, float h) {
    float m2 = h * h + 0.25;

    p.xz = abs(p.xz);
    p.xz = (p.z > p.x) ? p.zx : p.xz;
    p.xz -= 0.5;

    float3 q = float3(p.z, h * p.y - 0.5 * p.x, h * p.x + 0.5 * p.y);

    float s = max(-q.x, 0.0);
    float t = clamp((q.y - 0.5 * p.z) / (m2 + 0.25), 0.0, 1.0);

    float a = m2 * (q.x + s) * (q.x + s) + q.y * q.y;
    float b = m2 * (q.x + 0.5 * t) * (q.x + 0.5 * t) + (q.y - m2 * t) * (q.y - m2 * t);

    float d2 = min(q.y, -q.x * m2 - q.y * 0.5) > 0.0 ? 0.0 : min(a, b);

    return sqrt((d2 + q.z * q.z) / m2) * sgn(max(q.z, -p.y));
}

float sdRhombus(float3 p, float la, float lb, float h, float ra) {
    p = abs(p);
    float2 b = float2(la, lb);
    float f = clamp((ndot(b, b - 2.0 * p.xz)) / dot(b, b), -1.0, 1.0);
    float2 q = float2(length(p.xz - 0.5 * b * float2(1.0 - f, 1.0 + f)) * sgn(p.x * b.y + p.z * b.x - b.x * b.y) - ra, p.y - h);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0));
}

float sdHorseshoe(float3 p, float2 c, float r, float le, float2 w) {
    p.x = abs(p.x);
    float l = length(p.xy);
    float2x2 rot = float2x2(float2(-c.x, c.y), float2(c.y, c.x));
    p.xy = rot * p.xy;
    p.xy = float2((p.y > 0.0 || p.x > 0.0) ? p.x : l * sgn(-c.x), (p.x > 0.0) ? p.y : l);
    p.xy = float2(p.x, abs(p.y - r)) - float2(le, 0.0);

    float2 q = float2(length(max(p.xy, 0.0)) + min(0.0, max(p.x, p.y)), p.z);
    float2 d = abs(q) - w;
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

float sdU(float3 p, float r, float le, float2 w) {
    p.x = (p.y > 0.0) ? abs(p.x) : length(p.xy);
    p.x = abs(p.x - r);
    p.y = p.y - le;
    float k = max(p.x, p.y);
    float2 q = float2((k < 0.0) ? -k : length(max(p.xy, 0.0)), abs(p.z)) - w;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

float2 opU(float2 d1, float2 d2) {
    return (d1.x < d2.x) ? d1 : d2;
}

float2 map(float3 pos) {
    float2 res = float2(pos.y, 0.0);

    if (sdBox(pos - float3(-2.0, 0.3, 0.25), float3(0.3, 0.3, 1.0)) < res.x) {
        res = opU(res, float2(sdSphere(pos - float3(-2.0, 0.25, 0.0), 0.25), 26.9));
        float3 p = pos - float3(-2.0, 0.25, 1.0);
        res = opU(res, float2(sdRhombus(float3(p.x, p.z, p.y), 0.15, 0.25, 0.04, 0.08), 17.0));
    }

    if (sdBox(pos - float3(0.0, 0.3, -1.0), float3(0.35, 0.3, 2.5)) < res.x) {
        res = opU(res, float2(sdCappedTorus((pos - float3(0.0, 0.30, 1.0)) * float3(1, -1, 1), float2(0.866025, -0.5), 0.25, 0.05), 25.0));
        res = opU(res, float2(sdBoxFrame(pos - float3(0.0, 0.25, 0.0), float3(0.3, 0.25, 0.2), 0.025), 16.9));
        res = opU(res, float2(sdCone(pos - float3(0.0, 0.45, -1.0), float2(0.6, 0.8), 0.45), 55.0));
        res = opU(res, float2(sdCappedCone(pos - float3(0.0, 0.25, -2.0), 0.25, 0.25, 0.1), 13.67));
        res = opU(res, float2(sdSolidAngle(pos - float3(0.0, 0.00, -3.0), float2(3, 4) / 5.0, 0.4), 49.13));
    }

    if (sdBox(pos - float3(1.0, 0.3, -1.0), float3(0.35, 0.3, 2.5)) < res.x) {
        float3 p1 = pos - float3(1.0, 0.30, 1.0);
        res = opU(res, float2(sdTorus(float3(p1.x, p1.z, p1.y), float2(0.25, 0.05)), 7.1));
        res = opU(res, float2(sdBox(pos - float3(1.0, 0.25, 0.0), float3(0.3, 0.25, 0.1)), 3.0));
        res = opU(res, float2(sdCapsule(pos - float3(1.0, 0.00, -1.0), float3(-0.1, 0.1, -0.1), float3(0.2, 0.4, 0.2), 0.1), 31.9));
        res = opU(res, float2(sdCylinder(pos - float3(1.0, 0.25, -2.0), float2(0.15, 0.25)), 8.0));
        res = opU(res, float2(sdHexPrism(pos - float3(1.0, 0.2, -3.0), float2(0.2, 0.05)), 18.4));
    }

    if (sdBox(pos - float3(-1.0, 0.35, -1.0), float3(0.35, 0.35, 2.5)) < res.x) {
        res = opU(res, float2(sdPyramid(pos - float3(-1.0, -0.6, -3.0), 1.0), 13.56));
        res = opU(res, float2(sdOctahedron(pos - float3(-1.0, 0.15, -2.0), 0.35), 23.56));
        res = opU(res, float2(sdTriPrism(pos - float3(-1.0, 0.15, -1.0), float2(0.3, 0.05)), 43.5));
        res = opU(res, float2(sdEllipsoid(pos - float3(-1.0, 0.25, 0.0), float3(0.2, 0.25, 0.05)), 43.17));
        res = opU(res, float2(sdHorseshoe(pos - float3(-1.0, 0.25, 1.0), float2(cos(1.3), sin(1.3)), 0.2, 0.3, float2(0.03, 0.08)), 11.5));
    }

    if (sdBox(pos - float3(2.0, 0.3, -1.0), float3(0.35, 0.3, 2.5)) < res.x) {
        res = opU(res, float2(sdOctogonPrism(pos - float3(2.0, 0.2, -3.0), 0.2, 0.05), 51.8));
        res = opU(res, float2(sdCylinder(pos - float3(2.0, 0.14, -2.0), float3(0.1, -0.1, 0.0), float3(-0.2, 0.35, 0.1), 0.08), 31.2));
        res = opU(res, float2(sdCappedCone(pos - float3(2.0, 0.09, -1.0), float3(0.1, 0.0, 0.0), float3(-0.2, 0.40, 0.1), 0.15, 0.05), 46.1));
        res = opU(res, float2(sdRoundCone(pos - float3(2.0, 0.15, 0.0), float3(0.1, 0.0, 0.0), float3(-0.1, 0.35, 0.1), 0.15, 0.05), 51.7));
        res = opU(res, float2(sdRoundCone(pos - float3(2.0, 0.20, 1.0), 0.2, 0.1, 0.3), 37.0));
    }

    return res;
}

float2 iBox(float3 ro, float3 rd, float3 rad) {
    float3 m = 1.0 / rd;
    float3 n = m * ro;
    float3 k = abs(m) * rad;
    float3 t1 = -n - k;
    float3 t2 = -n + k;
    return float2(max(max(t1.x, t1.y), t1.z), min(min(t2.x, t2.y), t2.z));
}

float2 raycast(float3 ro, float3 rd) {
    float2 res = float2(-1.0, -1.0);

    float tmin = 1.0;
    float tmax = 20.0;

    float tp1 = (0.0 - ro.y) / rd.y;
    if (tp1 > 0.0) {
        tmax = min(tmax, tp1);
        res = float2(tp1, 1.0);
    }

    float2 tb = iBox(ro - float3(0.0, 0.4, -0.5), rd, float3(2.5, 0.41, 3.0));
    if (tb.x < tb.y && tb.y > 0.0 && tb.x < tmax) {
        tmin = max(tb.x, tmin);
        tmax = min(tb.y, tmax);

        float t = tmin;
        for (int i = 0; i < 70 && t < tmax; i++) {
            float2 h = map(ro + rd * t);
            if (abs(h.x) < (0.0001 * t)) {
                res = float2(t, h.y);
                break;
            }
            t += h.x;
        }
    }

    return res;
}

float calcSoftshadow(float3 ro, float3 rd, float mint, float tmax) {
    float tp = (0.8 - ro.y) / rd.y;
    if (tp > 0.0) tmax = min(tmax, tp);

    float res = 1.0;
    float t = mint;
    for (int i = ZERO; i < 24; i++) {
        float h = map(ro + rd * t).x;
        float s = clamp(8.0 * h / t, 0.0, 1.0);
        res = min(res, s);
        t += clamp(h, 0.01, 0.2);
        if (res < 0.004 || t > tmax) break;
    }
    res = clamp(res, 0.0, 1.0);
    return res * res * (3.0 - 2.0 * res);
}

float3 calcNormal(float3 pos) {
    float3 n = float3(0.0);
    for (int i = ZERO; i < 4; i++) {
        float3 e = 0.5773 * (2.0 * float3(float(((i + 3) >> 1) & 1), float((i >> 1) & 1), float(i & 1)) - 1.0);
        n += e * map(pos + 0.0005 * e).x;
    }
    return normalize(n);
}

float calcAO(float3 pos, float3 nor) {
    float occ = 0.0;
    float sca = 1.0;
    for (int i = ZERO; i < 5; i++) {
        float h = 0.01 + 0.12 * float(i) / 4.0;
        float d = map(pos + h * nor).x;
        occ += (h - d) * sca;
        sca *= 0.95;
        if (occ > 0.35) break;
    }
    return clamp(1.0 - 3.0 * occ, 0.0, 1.0) * (0.5 + 0.5 * nor.y);
}

float checkerBoard(float2 p) {
    float2 ip = floor(p);
    return fmod(ip.x + ip.y, 2.0);
}

// =============================================================================
// PBR Helpers
// =============================================================================

float3 fresnelSchlick(float cos_theta, float3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

float3 fresnelSchlickRoughness(float cos_theta, float3 F0, float roughness) {
    return F0 + (max(float3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

float distributionGGX(float3 N, float3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float num = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return num / denom;
}

float geometrySchlickGGX(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;

    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return num / denom;
}

float geometrySmith(float3 N, float3 V, float3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = geometrySchlickGGX(NdotV, roughness);
    float ggx1 = geometrySchlickGGX(NdotL, roughness);
    return ggx1 * ggx2;
}

float3 calculatePBRLight(float3 L, float3 radiance, float3 N, float3 V, float3 albedo, float metallic, float roughness, float3 F0) {
    float3 H = normalize(V + L);

    float NDF = distributionGGX(N, H, roughness);
    float G = geometrySmith(N, V, L, roughness);
    float3 F = fresnelSchlick(max(dot(H, L), 0.0), F0);

    float3 numerator = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    float3 specular = numerator / denominator;

    float3 kS = F;
    float3 kD = float3(1.0) - kS;
    kD *= 1.0 - metallic;

    float NdotL = max(dot(N, L), 0.0);
    return (kD * albedo / PI + specular) * radiance * NdotL;
}

float calculateAttenuation(float distance, float range) {
    float attenuation = clamp(1.0 - pow(distance / range, 4.0), 0.0, 1.0);
    return attenuation * attenuation / (distance * distance + 1.0);
}

// =============================================================================
// Fragment Shader
// =============================================================================

fragment float4 raymarch_fragment_main(
    Vertex3DOutput in [[stage_in]],
    constant LightUniforms& lights [[buffer(1)]],
    texturecube<float> irradiance_map [[texture(5)]],
    texturecube<float> prefiltered_env [[texture(6)]],
    texture2d<float> brdf_lut [[texture(7)]],
    sampler samp [[sampler(5)]]
) {
    float3 ro = lights.camera_position.xyz;
    float3 rd = normalize(in.world_pos - ro);

    float2 hit = raycast(ro, rd);
    if (hit.x < 0.0) {
        discard_fragment();
    }

    float t = hit.x;
    float m = hit.y;
    float3 pos = ro + rd * t;

    float3 N = (m < 1.5) ? float3(0.0, 1.0, 0.0) : calcNormal(pos);
    float3 V = normalize(ro - pos);

    float ao = calcAO(pos, N);
    float shadow = calcSoftshadow(pos, normalize(-lights.directional_direction.xyz), 0.02, 4.0);

    float3 albedo;
    float metallic;
    float roughness;

    if (m < 1.5) {
        float checker = checkerBoard(pos.xz * 3.0);
        albedo = mix(float3(0.08), float3(0.18), checker);
        metallic = 0.0;
        roughness = 0.9;
    } else {
        albedo = clamp(0.2 + 0.2 * sin(m * 2.0 + float3(0.0, 1.0, 2.0)), 0.0, 1.0);
        float metal_mask = step(40.0, m);
        metallic = mix(0.0, 0.9, metal_mask);
        roughness = mix(0.55, 0.2, metal_mask);
    }

    roughness = clamp(roughness, 0.04, 1.0);
    float3 F0 = mix(float3(0.04), albedo, metallic);

    float3 Lo = float3(0.0);
    {
        float3 L = normalize(-lights.directional_direction.xyz);
        float3 radiance = lights.directional_color_intensity.rgb * lights.directional_color_intensity.a;
        Lo += calculatePBRLight(L, radiance * shadow, N, V, albedo, metallic, roughness, F0);
    }

    for (uint i = 0; i < lights.point_light_count && i < MAX_POINT_LIGHTS; i++) {
        float3 light_pos = lights.point_lights[i].position_range.xyz;
        float range = lights.point_lights[i].position_range.w;
        float3 light_color = lights.point_lights[i].color_intensity.rgb;
        float intensity = lights.point_lights[i].color_intensity.a;

        float3 L = light_pos - pos;
        float distance = length(L);
        if (distance < range) {
            L = normalize(L);
            float attenuation = calculateAttenuation(distance, range);
            float3 radiance = light_color * intensity * attenuation;
            Lo += calculatePBRLight(L, radiance, N, V, albedo, metallic, roughness, F0);
        }
    }

    for (uint i = 0; i < lights.spot_light_count && i < MAX_SPOT_LIGHTS; i++) {
        float3 light_pos = lights.spot_lights[i].position_range.xyz;
        float range = lights.spot_lights[i].position_range.w;
        float3 light_dir = lights.spot_lights[i].direction_outer.xyz;
        float outer_cos = lights.spot_lights[i].direction_outer.w;
        float3 light_color = lights.spot_lights[i].color_intensity.rgb;
        float intensity = lights.spot_lights[i].color_intensity.a;
        float inner_cos = lights.spot_lights[i].inner_pad.x;

        float3 L = light_pos - pos;
        float distance = length(L);
        if (distance < range) {
            L = normalize(L);
            float theta = dot(L, normalize(-light_dir));
            float epsilon = max(inner_cos - outer_cos, 0.0001);
            float spot_intensity = clamp((theta - outer_cos) / epsilon, 0.0, 1.0);
            if (spot_intensity > 0.0) {
                float attenuation = calculateAttenuation(distance, range);
                float3 radiance = light_color * intensity * attenuation * spot_intensity;
                Lo += calculatePBRLight(L, radiance, N, V, albedo, metallic, roughness, F0);
            }
        }
    }

    float3 ambient;
    if (lights.ibl_params.z > 0.5) {
        float NdotV = max(dot(N, V), 0.0);
        float3 R = reflect(-V, N);

        float3 F = fresnelSchlickRoughness(NdotV, F0, roughness);
        float3 kD = (1.0 - F) * (1.0 - metallic);
        float3 irradiance = irradiance_map.sample(samp, N).rgb;
        float3 diffuse = kD * irradiance * albedo;

        float lod = roughness * lights.ibl_params.y;
        float3 prefiltered = prefiltered_env.sample(samp, R, level(lod)).rgb;
        float2 brdf = brdf_lut.sample(samp, float2(NdotV, roughness)).rg;
        float3 specular = prefiltered * (F * brdf.x + brdf.y) * lights.ibl_params.w;

        ambient = (diffuse + specular) * ao * lights.ibl_params.x;
    } else {
        float3 ambient_color = lights.ambient_color_intensity.rgb * lights.ambient_color_intensity.a;
        ambient = ambient_color * albedo * ao;
    }

    float3 color = ambient + Lo;

    float3 x = color;
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    color = clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
    color = pow(color, float3(1.0 / 2.2));

    return float4(color, 1.0);
}
