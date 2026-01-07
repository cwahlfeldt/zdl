const std = @import("std");
const quickjs = @import("quickjs");

const Vec2 = @import("../../math/vec2.zig").Vec2;
const Vec3 = @import("../../math/vec3.zig").Vec3;
const Quat = @import("../../math/quat.zig").Quat;

const JSContext = @import("../js_context.zig").JSContext;
const bindings = @import("bindings.zig");

/// Register math types and utilities on the global object.
pub fn register(ctx: *JSContext) !void {
    // Create basic Math object since we skip intrinsics
    const math_code =
        \\if (typeof Math === 'undefined') {
        \\var Math = {
        \\    sqrt: function(x) {
        \\        if (x < 0) return 0 / 0;  // NaN
        \\        if (x === 0) return 0;
        \\        if (x === 1) return 1;
        \\        // Binary search for square root
        \\        var low = 0;
        \\        var high = x > 1 ? x : 1;
        \\        var mid = 0;
        \\        for (var i = 0; i < 50; i++) {
        \\            mid = low + (high - low) * 0.5;
        \\            var square = mid * mid;
        \\            var diff = square - x;
        \\            if (diff < 0) diff = -diff;  // abs without calling Math.abs
        \\            if (diff < 0.000001) break;
        \\            if (square < x) low = mid;
        \\            else high = mid;
        \\        }
        \\        return mid;
        \\    },
        \\    abs: function(x) { return x < 0 ? -x : x; },
        \\    sin: function(x) { return __native_sin(x); },
        \\    cos: function(x) { return __native_cos(x); },
        \\    tan: function(x) { return __native_tan(x); },
        \\    asin: function(x) { return __native_asin(x); },
        \\    acos: function(x) { return __native_acos(x); },
        \\    atan: function(x) { return __native_atan(x); },
        \\    atan2: function(y, x) { return __native_atan2(y, x); },
        \\    floor: function(x) { return x >= 0 ? (x | 0) : ((x | 0) - 1); },
        \\    ceil: function(x) { return x >= 0 ? ((x | 0) + (x % 1 !== 0 ? 1 : 0)) : (x | 0); },
        \\    round: function(x) { return Math.floor(x + 0.5); },
        \\    min: function(a, b) { return a < b ? a : b; },
        \\    max: function(a, b) { return a > b ? a : b; },
        \\    pow: function(x, y) { return __native_pow(x, y); },
        \\    exp: function(x) { return __native_exp(x); },
        \\    log: function(x) { return __native_log(x); },
        \\    PI: 3.141592653589793,
        \\    E: 2.718281828459045,
        \\    clamp: function(x, min, max) { return Math.max(min, Math.min(max, x)); }
        \\};
        \\}
        \\
        \\// Native math functions will be provided by Zig
        \\// For now, provide stub implementations using power series
        \\if (typeof __native_sqrt === 'undefined') { __native_sqrt = function(x) {
        \\        if (x < 0) return 0 / 0;
        \\        if (x === 0) return 0;
        \\        var guess = x / 2;
        \\        for (var i = 0; i < 20; i++) {
        \\            guess = (guess + x / guess) / 2;
        \\        }
        \\        return guess;
        \\    }; }
        \\if (typeof __native_sin === 'undefined') { __native_sin = function(x) {
        \\        x = x % (2 * 3.141592653589793);
        \\        var result = 0, term = x;
        \\        for (var n = 1; n <= 10; n++) {
        \\            result += term;
        \\            term *= -x * x / (2 * n * (2 * n + 1));
        \\        }
        \\        return result;
        \\    }; }
        \\if (typeof __native_cos === 'undefined') { __native_cos = function(x) {
        \\        x = x % (2 * 3.141592653589793);
        \\        var result = 0, term = 1;
        \\        for (var n = 0; n <= 10; n++) {
        \\            result += term;
        \\            term *= -x * x / ((2 * n + 1) * (2 * n + 2));
        \\        }
        \\        return result;
        \\    }; }
        \\if (typeof __native_tan === 'undefined') { __native_tan = function(x) { return __native_sin(x) / __native_cos(x); }; }
        \\if (typeof __native_asin === 'undefined') { __native_asin = function(x) { return x; }; } // Stub
        \\if (typeof __native_acos === 'undefined') { __native_acos = function(x) { return 1.5707963267948966 - x; }; } // Stub
        \\if (typeof __native_atan === 'undefined') { __native_atan = function(x) { return x; }; } // Stub
        \\if (typeof __native_atan2 === 'undefined') { __native_atan2 = function(y, x) { return __native_atan(y / x); }; } // Stub
        \\if (typeof __native_pow === 'undefined') { __native_pow = function(x, y) {
        \\        if (y === 0) return 1;
        \\        if (y === 1) return x;
        \\        var result = 1;
        \\        var abs_y = y < 0 ? -y : y;
        \\        for (var i = 0; i < abs_y; i++) result *= x;
        \\        return y < 0 ? 1 / result : result;
        \\    }; }
        \\if (typeof __native_exp === 'undefined') { __native_exp = function(x) { return __native_pow(2.718281828459045, x); }; }
        \\if (typeof __native_log === 'undefined') { __native_log = function(x) { return x; }; } // Stub
        \\true;
    ;
    const math_result = try ctx.eval(math_code, "<math-builtin>");
    ctx.freeValue(math_result);

    // Create Vec2 constructor function
    const vec2_code =
        \\function Vec2(x, y) {
        \\    this.x = x || 0;
        \\    this.y = y || 0;
        \\}
        \\Vec2.prototype.add = function(other) {
        \\    return new Vec2(this.x + other.x, this.y + other.y);
        \\};
        \\Vec2.prototype.sub = function(other) {
        \\    return new Vec2(this.x - other.x, this.y - other.y);
        \\};
        \\Vec2.prototype.mul = function(s) {
        \\    return new Vec2(this.x * s, this.y * s);
        \\};
        \\Vec2.prototype.div = function(s) {
        \\    return new Vec2(this.x / s, this.y / s);
        \\};
        \\Vec2.prototype.dot = function(other) {
        \\    return this.x * other.x + this.y * other.y;
        \\};
        \\Vec2.prototype.length = function() {
        \\    return Math.sqrt(this.x * this.x + this.y * this.y);
        \\};
        \\Vec2.prototype.normalize = function() {
        \\    var len = this.length();
        \\    if (len === 0) return new Vec2(0, 0);
        \\    return this.div(len);
        \\};
        \\Vec2.prototype.toString = function() {
        \\    return 'Vec2(' + this.x + ', ' + this.y + ')';
        \\};
        \\Vec2.zero = function() { return new Vec2(0, 0); };
        \\Vec2.one = function() { return new Vec2(1, 1); };
        \\Vec2;
    ;
    const vec2_ctor = try ctx.eval(vec2_code, "<math>");
    try ctx.setGlobal("Vec2", vec2_ctor);

    // Create Vec3 constructor function
    const vec3_code =
        \\function Vec3(x, y, z) {
        \\    this.x = x || 0;
        \\    this.y = y || 0;
        \\    this.z = z || 0;
        \\}
        \\Vec3.prototype.add = function(other) {
        \\    return new Vec3(this.x + other.x, this.y + other.y, this.z + other.z);
        \\};
        \\Vec3.prototype.sub = function(other) {
        \\    return new Vec3(this.x - other.x, this.y - other.y, this.z - other.z);
        \\};
        \\Vec3.prototype.mul = function(s) {
        \\    return new Vec3(this.x * s, this.y * s, this.z * s);
        \\};
        \\Vec3.prototype.div = function(s) {
        \\    return new Vec3(this.x / s, this.y / s, this.z / s);
        \\};
        \\Vec3.prototype.dot = function(other) {
        \\    return this.x * other.x + this.y * other.y + this.z * other.z;
        \\};
        \\Vec3.prototype.cross = function(other) {
        \\    return new Vec3(
        \\        this.y * other.z - this.z * other.y,
        \\        this.z * other.x - this.x * other.z,
        \\        this.x * other.y - this.y * other.x
        \\    );
        \\};
        \\Vec3.prototype.length = function() {
        \\    return Math.sqrt(this.x * this.x + this.y * this.y + this.z * this.z);
        \\};
        \\Vec3.prototype.normalize = function() {
        \\    var len = this.length();
        \\    if (len === 0) return new Vec3(0, 0, 0);
        \\    return this.div(len);
        \\};
        \\Vec3.prototype.distance = function(other) {
        \\    return this.sub(other).length();
        \\};
        \\Vec3.prototype.lerp = function(other, t) {
        \\    return new Vec3(
        \\        this.x + (other.x - this.x) * t,
        \\        this.y + (other.y - this.y) * t,
        \\        this.z + (other.z - this.z) * t
        \\    );
        \\};
        \\Vec3.prototype.negate = function() {
        \\    return new Vec3(-this.x, -this.y, -this.z);
        \\};
        \\Vec3.prototype.toString = function() {
        \\    return 'Vec3(' + this.x + ', ' + this.y + ', ' + this.z + ')';
        \\};
        \\Vec3.zero = function() { return new Vec3(0, 0, 0); };
        \\Vec3.one = function() { return new Vec3(1, 1, 1); };
        \\Vec3.up = function() { return new Vec3(0, 1, 0); };
        \\Vec3.down = function() { return new Vec3(0, -1, 0); };
        \\Vec3.forward = function() { return new Vec3(0, 0, -1); };
        \\Vec3.back = function() { return new Vec3(0, 0, 1); };
        \\Vec3.right = function() { return new Vec3(1, 0, 0); };
        \\Vec3.left = function() { return new Vec3(-1, 0, 0); };
        \\Vec3;
    ;
    const vec3_ctor = try ctx.eval(vec3_code, "<math>");
    try ctx.setGlobal("Vec3", vec3_ctor);

    // Create Quat constructor function
    const quat_code =
        \\function Quat(x, y, z, w) {
        \\    this.x = x || 0;
        \\    this.y = y || 0;
        \\    this.z = z || 0;
        \\    this.w = w !== undefined ? w : 1;
        \\}
        \\Quat.prototype.mul = function(other) {
        \\    return new Quat(
        \\        this.w * other.x + this.x * other.w + this.y * other.z - this.z * other.y,
        \\        this.w * other.y - this.x * other.z + this.y * other.w + this.z * other.x,
        \\        this.w * other.z + this.x * other.y - this.y * other.x + this.z * other.w,
        \\        this.w * other.w - this.x * other.x - this.y * other.y - this.z * other.z
        \\    );
        \\};
        \\Quat.prototype.length = function() {
        \\    return Math.sqrt(this.x * this.x + this.y * this.y + this.z * this.z + this.w * this.w);
        \\};
        \\Quat.prototype.normalize = function() {
        \\    var len = this.length();
        \\    if (len === 0) return Quat.identity();
        \\    return new Quat(this.x / len, this.y / len, this.z / len, this.w / len);
        \\};
        \\Quat.prototype.conjugate = function() {
        \\    return new Quat(-this.x, -this.y, -this.z, this.w);
        \\};
        \\Quat.prototype.rotateVec3 = function(v) {
        \\    var qv = new Quat(v.x, v.y, v.z, 0);
        \\    var result = this.mul(qv).mul(this.conjugate());
        \\    return new Vec3(result.x, result.y, result.z);
        \\};
        \\Quat.prototype.toString = function() {
        \\    return 'Quat(' + this.x + ', ' + this.y + ', ' + this.z + ', ' + this.w + ')';
        \\};
        \\Quat.identity = function() { return new Quat(0, 0, 0, 1); };
        \\Quat.fromAxisAngle = function(axis, angle) {
        \\    var half = angle * 0.5;
        \\    var s = Math.sin(half);
        \\    var c = Math.cos(half);
        \\    var n = axis.normalize();
        \\    return new Quat(n.x * s, n.y * s, n.z * s, c);
        \\};
        \\Quat.fromEuler = function(pitch, yaw, roll) {
        \\    var cy = Math.cos(yaw * 0.5);
        \\    var sy = Math.sin(yaw * 0.5);
        \\    var cp = Math.cos(pitch * 0.5);
        \\    var sp = Math.sin(pitch * 0.5);
        \\    var cr = Math.cos(roll * 0.5);
        \\    var sr = Math.sin(roll * 0.5);
        \\    return new Quat(
        \\        sr * cp * cy - cr * sp * sy,
        \\        cr * sp * cy + sr * cp * sy,
        \\        cr * cp * sy - sr * sp * cy,
        \\        cr * cp * cy + sr * sp * sy
        \\    );
        \\};
        \\Quat.slerp = function(a, b, t) {
        \\    var dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
        \\    if (dot < 0) {
        \\        b = new Quat(-b.x, -b.y, -b.z, -b.w);
        \\        dot = -dot;
        \\    }
        \\    if (dot > 0.9995) {
        \\        return new Quat(
        \\            a.x + t * (b.x - a.x),
        \\            a.y + t * (b.y - a.y),
        \\            a.z + t * (b.z - a.z),
        \\            a.w + t * (b.w - a.w)
        \\        ).normalize();
        \\    }
        \\    var theta = Math.acos(dot);
        \\    var sinTheta = Math.sin(theta);
        \\    var wa = Math.sin((1 - t) * theta) / sinTheta;
        \\    var wb = Math.sin(t * theta) / sinTheta;
        \\    return new Quat(
        \\        wa * a.x + wb * b.x,
        \\        wa * a.y + wb * b.y,
        \\        wa * a.z + wb * b.z,
        \\        wa * a.w + wb * b.w
        \\    );
        \\};
        \\Quat;
    ;
    const quat_ctor = try ctx.eval(quat_code, "<math>");
    try ctx.setGlobal("Quat", quat_ctor);

    // Add Math utilities
    const math_utils =
        \\Math.clamp = function(value, min, max) {
        \\    return Math.min(Math.max(value, min), max);
        \\};
        \\Math.lerp = function(a, b, t) {
        \\    return a + (b - a) * t;
        \\};
        \\Math.smoothstep = function(edge0, edge1, x) {
        \\    var t = Math.clamp((x - edge0) / (edge1 - edge0), 0, 1);
        \\    return t * t * (3 - 2 * t);
        \\};
        \\Math.inverseLerp = function(a, b, value) {
        \\    if (a === b) return 0;
        \\    return (value - a) / (b - a);
        \\};
        \\Math.remap = function(value, inMin, inMax, outMin, outMax) {
        \\    var t = Math.inverseLerp(inMin, inMax, value);
        \\    return Math.lerp(outMin, outMax, t);
        \\};
        \\Math.degToRad = function(degrees) {
        \\    return degrees * (Math.PI / 180);
        \\};
        \\Math.radToDeg = function(radians) {
        \\    return radians * (180 / Math.PI);
        \\};
        \\Math.TAU = Math.PI * 2;
        \\true;
    ;
    const utils_result = try ctx.eval(math_utils, "<math>");
    ctx.freeValue(utils_result);
}
