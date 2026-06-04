shader_type canvas_item;

// Vertical hover bob
uniform float hover_speed  : hint_range(0.3, 3.0) = 0.8;
uniform float hover_pixels : hint_range(0.0, 4.0) = 1.5;

// Amber hem glow (bottom of cloak)
uniform vec4  hem_tint      : source_color = vec4(0.831, 0.502, 0.227, 1.0);
uniform float hem_strength  : hint_range(0.0, 1.5) = 0.5;
uniform float hem_threshold : hint_range(0.5, 1.0) = 0.7;

// Movement intensity — 0.0 = idle, 1.0 = full move
// Tweened by warrior.gd on MOVE enter/exit
uniform float move_intensity : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	float speed  = hover_speed  * (1.0 + move_intensity * 0.45);
	float bob_y  = hover_pixels * (1.0 + move_intensity * 1.4);
	float sway_x = move_intensity * 1.2;  // subtle horizontal pendulum during movement

	VERTEX.y += sin(TIME * speed) * bob_y;
	VERTEX.x += sin(TIME * speed * 0.65 + 1.0) * sway_x;
}

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
