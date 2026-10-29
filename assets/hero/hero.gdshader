shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;
uniform sampler2D front_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float tint_flash = 0.0;
void fragment() {
	vec3 back = COLOR.rgb;
	back = mix(pow((back + 0.055) / 1.055, vec3(2.4)), back / 12.92, step(back, vec3(0.04045)));
	vec3 front = texture(front_tex, UV).rgb;
	ALBEDO = mix(mix(back, front, COLOR.a), vec3(1.0), tint_flash);
	ROUGHNESS = 1.0;
}
