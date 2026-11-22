shader_type spatial;
// 戦場の地面。画像（テクスチャ）を使わず、計算だけで土とコンクリートのムラを作る。
// 近くは細かいざらつきと凹凸、遠くはのっぺりさせて、ちらつきと負荷を抑える。

// 土の暗い色
uniform vec3 color_dirt_dark : source_color = vec3(0.21, 0.20, 0.16);
// 土の明るい色
uniform vec3 color_dirt_light : source_color = vec3(0.34, 0.32, 0.26);
// コンクリートの色
uniform vec3 color_concrete : source_color = vec3(0.40, 0.40, 0.38);
// 舗装の継ぎ目の間隔（メートル）
uniform float slab_size = 12.0;
// 細かい凹凸の強さ
uniform float bump_strength = 0.55;
// 細かい模様が見える距離（メートル）
uniform float detail_near = 70.0;
uniform float detail_far = 300.0;

varying vec3 world_pos;

// 乱数（同じ場所なら必ず同じ値）
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// なめらかな雑音
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 雑音を重ねて自然なムラにする
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = world_pos.xz;

	// カメラから遠いほど細かい模様を弱める
	float dist = length(w - CAMERA_POSITION_WORLD.xz);
	float detail = 1.0 - smoothstep(detail_near, detail_far, dist);

	float macro = fbm(w * 0.011);           // 大きなムラ（100m くらい）
	float mid = fbm(w * 0.09);              // 中くらいのムラ（10m くらい）
	float grain = vnoise(w * 1.7);          // 砂のざらつき

	// 舗装の板と継ぎ目
	vec2 cell = abs(fract(w / slab_size) - 0.5);
	float joint = smoothstep(0.455, 0.497, max(cell.x, cell.y));
	float slab_id = hash12(floor(w / slab_size));

	// 土 → コンクリートへ、大きなムラで切り替える
	vec3 base = mix(color_dirt_dark, color_dirt_light, macro);
	float paved = smoothstep(0.52, 0.78, macro);
	vec3 pave = color_concrete * (0.88 + 0.24 * slab_id);
	base = mix(base, pave, paved);

	// 中くらいのムラと砂のざらつきで明暗を付ける
	base *= 0.86 + 0.28 * mid;
	base *= 0.94 + 0.12 * grain * detail;
	// 継ぎ目は暗く
	base = mix(base, base * 0.72, joint * (0.35 + 0.45 * paved));

	ALBEDO = base;
	// 濡れたような反射にならないよう、ざらついた質感にする
	ROUGHNESS = clamp(0.95 - 0.18 * paved + 0.06 * grain, 0.55, 1.0);
	SPECULAR = 0.35;

	// 近くだけ細かい凹凸を出す（高さの差から面の向きを作る）
	if (detail > 0.01) {
		float e = 0.6;
		float hx = fbm((w + vec2(e, 0.0)) * 0.22) - fbm((w - vec2(e, 0.0)) * 0.22);
		float hz = fbm((w + vec2(0.0, e)) * 0.22) - fbm((w - vec2(0.0, e)) * 0.22);
		float s = bump_strength * detail;
		NORMAL_MAP = vec3(0.5 - hx * s, 0.5 + hz * s, 1.0);
		NORMAL_MAP_DEPTH = 1.0;
	}
}
