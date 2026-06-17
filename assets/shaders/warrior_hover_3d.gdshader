shader_type spatial;
// 3D port of warrior_hover.gdshader's hem/shimmer (the canvas_item version stays
// for the 2D path). Drawn as an ADDITIVE overlay quad layered over the warrior's
// base billboard: only the amber cloak hem + lavender top shimmer add colour, and
// only where the base sprite is opaque (the cloak). The base Sprite3D is untouched.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

// The overlay samples the SAME 8-dir sheet the base billboard shows (kept in sync
// from WarriorSync), so UVs line up 1:1.
uniform sampler2D tex : source_color, filter_nearest;
uniform float hover_speed   : hint_range(0.3, 3.0) = 0.8;
uniform vec4  hem_tint      : source_color = vec4(0.831, 0.502, 0.227, 1.0);
uniform float hem_strength  : hint_range(0.0, 1.5) = 0.5;
uniform float hem_threshold : hint_range(0.5, 1.0) = 0.7;
uniform float move_intensity : hint_range(0.0, 1.0) = 0.0;
// UV.y direction differs between Sprite3D and QuadMesh; flip so "hem" is the
// visual bottom of the sprite.
uniform bool  flip_v = false;

void vertex() {
	// Full camera billboard, keeping the node's scale (matches the base Sprite3D).
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 uv = vec2(UV.x, flip_v ? 1.0 - UV.y : UV.y);
	vec4 col = texture(tex, uv);
	if (col.a < 0.05) {
		discard;
	}

	// Amber hem at the cloak bottom, intensifying when moving.
	float hem_boost = 1.0 + move_intensity * 0.7;
	float hem_mask  = smoothstep(hem_threshold, 1.0, uv.y);
	float pulse     = (sin(TIME * hover_speed * 1.4) + 1.0) * 0.5;
	vec3  add = hem_tint.rgb * (hem_mask * pulse * hem_strength * hem_boost);

	// Lavender edge shimmer at the top portion, only while moving.
	float top_mask = smoothstep(0.35, 0.0, uv.y);
	float shimmer  = (sin(TIME * hover_speed * 2.1 + uv.x * 8.0) + 1.0) * 0.5;
	vec3  lavender = vec3(0.627, 0.502, 0.878);  // #A080E0
	add += lavender * (top_mask * shimmer * move_intensity * 0.18);

	ALBEDO = add;
	ALPHA = col.a;  // ADD blend premultiplies by alpha -> tint lands on the cloak
}
