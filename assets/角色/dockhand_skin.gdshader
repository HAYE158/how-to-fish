shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 skin_color : source_color = vec4(0.97, 0.97, 0.97, 1.0);
uniform sampler2D skin_paint : source_color, hint_default_transparent, filter_linear, repeat_disable;

void fragment() {
	vec4 paint = texture(skin_paint, UV);
	ALBEDO = mix(skin_color.rgb, paint.rgb, paint.a);
	ROUGHNESS = 0.83;
	SPECULAR = 0.26;
}
