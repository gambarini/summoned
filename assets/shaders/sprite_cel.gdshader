shader_type spatial;
render_mode specular_disabled, diffuse_lambert, cull_disabled;

// Scattered ground-detail / foliage SPRITE (the t3ssel8r / David-Holland approach):
// a small textured quad laid over the terrain. UV-sampled (sprites are authored in
// UV, not world-tiled), alpha-cut so the silhouette is crisp, and lit with the SAME
// cel light() as cel_triplanar — so a FLAT, ground-aligned decal (NORMAL +Y, like the
// ground) takes the same light and blends in ("evenly lit to blend with the terrain").
// billboard=true makes it camera-facing for upright foliage (grass/weeds).

uniform sampler2D albedo_tex : source_color, filter_nearest;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float bands = 2.0;
uniform float light_gain = 0.3;
uniform float alpha_cut = 0.5;
uniform bool billboard = false;

void vertex() {
	if (billboard) {
		// Camera-facing, preserving the model's scale (orthographic-safe).
		mat4 mv = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		mv = mv * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = mv;
	}
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	if (c.a < alpha_cut) {
		discard;
	}
	ALBEDO = c.rgb * tint.rgb;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0);
	float q = floor(ndl * bands + 0.5) / bands;  // hard-stepped, matches cel_triplanar
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * q * light_gain;
}
