shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;

// Depth-based pixel outline overlay (t3ssel8r-style), drawn as a full-screen quad
// in the TRANSPARENT pass so DEPTH_TEXTURE is fully populated by the opaque scene
// and SCREEN_TEXTURE ordering is never a concern. It darkens two kinds of edge:
//   * SILHOUETTE  -- a foreshorten-corrected first-difference of view-space depth,
//     so a far object against a near one inks, but a steeply-slanted ground plane
//     (large but smooth depth gradient) does NOT false-edge. Drawn SINGLE-SIDED:
//     only the nearer (front) fragment of a depth discontinuity inks, so the line
//     is one texel wide and hugs the silhouette instead of a two-texel band
//     straddling it.
//   * CREASE      -- a Laplacian of view-space depth, which spikes where the
//     surface slope changes (a box corner) yet stays ~0 on any flat (even slanted)
//     surface.
// View-space normal is reconstructed from neighbour positions purely to drive the
// foreshorten correction. Works in any renderer (no normal-roughness buffer).

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec2 view_size = vec2(326.0, 186.0);  // padded SubViewport size in texels
uniform float depth_threshold = 0.35;          // silhouette sensitivity (view units)
uniform float normal_threshold = 0.30;         // crease (Laplacian) sensitivity
uniform vec3 outline_color : source_color = vec3(0.10, 0.12, 0.16);
uniform float outline_strength = 0.85;

// Reconstruct view-space position from a depth sample at the given screen UV.
vec3 view_pos(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).x;
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return v.xyz / v.w;
}

void vertex() {
	// Full-screen quad in clip space (QuadMesh size 2 -> VERTEX in [-1,1]).
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 texel = 1.0 / view_size;
	mat4 inv_proj = INV_PROJECTION_MATRIX;

	vec3 p_c = view_pos(SCREEN_UV, inv_proj);
	vec3 p_l = view_pos(SCREEN_UV + vec2(-texel.x, 0.0), inv_proj);
	vec3 p_r = view_pos(SCREEN_UV + vec2(texel.x, 0.0), inv_proj);
	vec3 p_u = view_pos(SCREEN_UV + vec2(0.0, -texel.y), inv_proj);
	vec3 p_d = view_pos(SCREEN_UV + vec2(0.0, texel.y), inv_proj);

	// Linear (view) depth: camera looks down -z, so depth = -z and is positive.
	float z_c = -p_c.z;
	float z_l = -p_l.z;
	float z_r = -p_r.z;
	float z_u = -p_u.z;
	float z_d = -p_d.z;

	// View normal from neighbour positions -> foreshorten factor (|n.z| ~ 1 face-on,
	// ~0 at grazing). Grazing surfaces get a larger depth tolerance so they don't ink.
	vec3 nrm = normalize(cross(p_r - p_l, p_d - p_u));
	float facing = clamp(abs(nrm.z), 0.08, 1.0);

	// Silhouette, SINGLE-SIDED: only ink the fragment that is NEARER than its
	// neighbour (a neighbour farther away by > tolerance). This keeps the line one
	// texel wide, hugging the front object, instead of a two-texel band where both
	// the near and far sides of the discontinuity light up.
	float d_far = max(max(z_l - z_c, z_r - z_c), max(z_u - z_c, z_d - z_c));
	float sil = step(depth_threshold / facing, d_far);

	// Crease: Laplacian of depth spikes at slope changes, ~0 on flat/slanted planes.
	float lap = abs((z_l + z_r + z_u + z_d) - 4.0 * z_c);
	float crease = step(normal_threshold / facing, lap);

	float edge = max(sil, crease);
	ALBEDO = outline_color;
	ALPHA = edge * outline_strength;
}
