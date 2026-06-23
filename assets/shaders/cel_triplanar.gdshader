shader_type spatial;
render_mode specular_disabled, diffuse_lambert;

// Triplanar variant of cel.gdshader for the look-match spike. Same flat cel/toon
// light() quantisation, but ALBEDO comes from a tiling pixel-art texture sampled
// in WORLD space (triplanar) so the grain stays locked to the surface and does
// NOT swim when the orthographic camera orbits — the key requirement for keeping
// full rotation (see docs/RENDERING_3D.md). Nearest filter + repeat keep it pixel-art.

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float texture_scale = 0.7;   // tiles per world unit (larger = finer/denser)
uniform float blend_sharpness = 4.0; // triplanar seam tightness
uniform float bands = 2.0;           // number of hard light steps (match cel.gdshader)
uniform float light_gain = 0.3;      // directional contribution (low = soft)

// Macro value-variation: a SECOND, very-low-frequency noise sampled in world space
// that modulates the tiled albedo's VALUE, so the 64px tile's repeat is broken across
// the whole surface at once (the explore-scale grid fix). World-sampled => stationary
// under camera orbit (no swim), same as the base grain. Survives the palette snap
// because it is large-scale value drift (lands on different ramp steps), not a within-
// block gradient. macro_strength 0 = identity (production default until tuned in).
uniform sampler2D macro_noise : hint_default_white, filter_linear, repeat_enable;
uniform float macro_scale = 0.03;    // tiles per world unit (small = broad patches, tens of units)
uniform float macro_strength = 0.0;  // 0..~0.4 value excursion; 0 keeps current look exactly

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Triplanar blend weights from the world normal.
	vec3 bw = pow(abs(v_world_normal), vec3(blend_sharpness));
	bw /= (bw.x + bw.y + bw.z);

	vec2 uv_x = v_world_pos.zy * texture_scale;
	vec2 uv_y = v_world_pos.xz * texture_scale;
	vec2 uv_z = v_world_pos.xy * texture_scale;

	vec3 cx = texture(albedo_tex, uv_x).rgb;
	vec3 cy = texture(albedo_tex, uv_y).rgb;
	vec3 cz = texture(albedo_tex, uv_z).rgb;

	ALBEDO = (cx * bw.x + cy * bw.y + cz * bw.z) * tint.rgb;
	// Broad value drift (m~0.5 mean -> no change; strength scales the excursion).
	float m = texture(macro_noise, v_world_pos.xz * macro_scale).r;
	ALBEDO *= 1.0 + (m - 0.5) * 2.0 * macro_strength;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0);
	float q = floor(ndl * bands + 0.5) / bands;  // hard-stepped 0..1
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * q * light_gain;
}
