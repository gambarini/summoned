shader_type canvas_item;

// Hover bob + sway are driven in warrior.gd (_update_hover) so the Hollow nodes
// share the offset; this shader is fragment-only. hover_speed still paces the
// fragment animation below.
uniform float hover_speed  : hint_range(0.3, 3.0) = 0.8;

// Amber hem glow (bottom of cloak)
uniform vec4  hem_tint      : source_color = vec4(0.831, 0.502, 0.227, 1.0);
uniform float hem_strength  : hint_range(0.0, 1.5) = 0.5;
uniform float hem_threshold : hint_range(0.5, 1.0) = 0.7;

// Movement intensity — 0.0 = idle, 1.0 = full move
// Tweened by warrior.gd on MOVE enter/exit
uniform float move_intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	if (col.a < 0.05) discard;

	// Hem glow intensifies when moving
	float hem_boost = 1.0 + move_intensity * 0.7;
	float hem_mask  = smoothstep(hem_threshold, 1.0, UV.y);
	float pulse     = (sin(TIME * hover_speed * 1.4) + 1.0) * 0.5;
	col.rgb = mix(col.rgb, hem_tint.rgb, hem_mask * pulse * hem_strength * hem_boost * col.a);

	// Subtle lavender edge shimmer during movement (top portion of sprite)
	float top_mask  = smoothstep(0.35, 0.0, UV.y);
	float shimmer   = (sin(TIME * hover_speed * 2.1 + UV.x * 8.0) + 1.0) * 0.5;
	vec3  lavender  = vec3(0.627, 0.502, 0.878);  // #A080E0
	col.rgb = mix(col.rgb, lavender, top_mask * shimmer * move_intensity * 0.18 * col.a);

	COLOR = col;
}
