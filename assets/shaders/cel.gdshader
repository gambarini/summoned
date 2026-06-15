shader_type spatial;
render_mode specular_disabled, diffuse_lambert;

// Flat cel/toon shading: quantises directional light into a few hard steps so
// each surface reads as flat authored regions with crisp boundaries (like the
// concept's hand-painted look) instead of a smooth 3D lighting ramp. Ambient
// from the environment is added automatically as the flat base value.

uniform vec4 albedo : source_color = vec4(0.5, 0.55, 0.62, 1.0);
uniform float bands = 2.0;       // number of light steps
uniform float light_gain = 0.4;  // how much the directional adds (low = soft)

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0);
	float q = floor(ndl * bands + 0.5) / bands;  // hard-stepped 0..1
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * q * light_gain;
}
