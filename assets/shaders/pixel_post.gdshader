shader_type canvas_item;

// Pixel-art post pass for the low-res 3D iso spike.
// 1) Sobel edge detection darkens silhouettes/creases into ink lines (the step
//    that makes 3D read as *drawn* rather than rendered).
// 2) Ordered (Bayer) dithering breaks smooth shading into stipple.
// 3) Every pixel snaps to a fixed authored palette.

uniform vec3 palette[16];
uniform int palette_count = 16;
uniform vec2 tex_size = vec2(320.0, 180.0);
uniform float dither_strength = 0.05;
uniform float edge_strength = 0.6;

const float bayer[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 texel = 1.0 / tex_size;
	vec3 col = texture(TEXTURE, UV).rgb;

	// Sobel on luminance over the 8 neighbours.
	float l00 = luma(texture(TEXTURE, UV + texel * vec2(-1.0, -1.0)).rgb);
	float l01 = luma(texture(TEXTURE, UV + texel * vec2(0.0, -1.0)).rgb);
	float l02 = luma(texture(TEXTURE, UV + texel * vec2(1.0, -1.0)).rgb);
	float l10 = luma(texture(TEXTURE, UV + texel * vec2(-1.0, 0.0)).rgb);
	float l12 = luma(texture(TEXTURE, UV + texel * vec2(1.0, 0.0)).rgb);
	float l20 = luma(texture(TEXTURE, UV + texel * vec2(-1.0, 1.0)).rgb);
	float l21 = luma(texture(TEXTURE, UV + texel * vec2(0.0, 1.0)).rgb);
	float l22 = luma(texture(TEXTURE, UV + texel * vec2(1.0, 1.0)).rgb);
	float gx = (l02 + 2.0 * l12 + l22) - (l00 + 2.0 * l10 + l20);
	float gy = (l20 + 2.0 * l21 + l22) - (l00 + 2.0 * l01 + l02);
	float edge = smoothstep(0.10, 0.30, sqrt(gx * gx + gy * gy));
	col *= (1.0 - edge * edge_strength);

	// Dither at the native low-res grid so the stipple is 1px.
	ivec2 p = ivec2(floor(UV * tex_size));
	int idx = (p.y % 4) * 4 + (p.x % 4);
	col += vec3((bayer[idx] / 16.0 - 0.5) * dither_strength);

	// Snap to nearest palette colour (constant loop bound for ES compat).
	float best = 1e9;
	vec3 chosen = col;
	for (int i = 0; i < 16; i++) {
		if (i >= palette_count) {
			break;
		}
		float dist = distance(col, palette[i]);
		if (dist < best) {
			best = dist;
			chosen = palette[i];
		}
	}
	COLOR = vec4(chosen, texture(TEXTURE, UV).a);
}
