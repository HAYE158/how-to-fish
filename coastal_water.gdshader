shader_type spatial;
render_mode blend_mix, cull_back, world_vertex_coords, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.12, 0.74, 0.69, 1.0);
uniform vec4 deep_color : source_color = vec4(0.045, 0.20, 0.40, 1.0);
uniform vec4 foam_color : source_color = vec4(0.87, 0.99, 0.96, 1.0);
uniform float absorption : hint_range(0.0, 2.0, 0.01) = 0.42;
uniform float visibility_depth : hint_range(0.5, 20.0, 0.1) = 4.8;
uniform float foam_width : hint_range(0.01, 1.0, 0.01) = 0.24;
uniform float wave_height : hint_range(0.0, 0.5, 0.01) = 0.12;
uniform float wave_speed : hint_range(0.0, 3.0, 0.05) = 0.85;
uniform float surface_detail : hint_range(0.0, 1.0, 0.01) = 0.65;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;

group_uniforms seabed;
uniform bool use_seabed_mask = false;
uniform sampler2D seabed_mask : hint_default_white, repeat_disable, filter_linear;
// World XZ of the texture's top-left corner, then its world width and depth.
uniform vec4 seabed_bounds = vec4(-20.0, -20.0, 40.0, 40.0);
group_uniforms;

const vec2 SWELL_A = vec2(1.14, 0.81);
const vec2 SWELL_B = vec2(-1.64, 1.32);
varying vec3 water_position;

float hash_cell(vec2 point) {
	return fract(sin(dot(point, vec2(41.37, 113.59))) * 23719.47);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 f = fract(point);
	vec2 weight = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), weight.x),
		mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + vec2(1.0)), weight.x),
		weight.y
	);
}

void vertex() {
	vec2 xz = VERTEX.xz;
	float phase_a = dot(xz, SWELL_A) - TIME * wave_speed;
	float phase_b = dot(xz, SWELL_B) - TIME * wave_speed * 1.46;
	VERTEX.y += wave_height * (0.66 * sin(phase_a) + 0.34 * sin(phase_b));
	water_position = VERTEX;
}

vec3 view_space_position(vec2 uv, float raw_depth, mat4 inverse_projection) {
	vec2 xy = uv * 2.0 - 1.0;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		float z = raw_depth * 2.0 - 1.0;
	#else
		float z = raw_depth;
	#endif
	vec4 point = inverse_projection * vec4(xy, z, 1.0);
	return point.xyz / point.w;
}

void fragment() {
	float raw_depth = texture(scene_depth, SCREEN_UV).r;
	float vertical_depth = 0.0;
	float optical_depth = 0.0;
	bool has_seabed = false;
	vec3 ground_position = vec3(0.0);
	float coverage = 1.0;
	if (use_seabed_mask) {
		vec2 uv = (water_position.xz - seabed_bounds.xy) / max(seabed_bounds.zw, vec2(0.001));
		coverage = 0.0;
		if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)))) {
			coverage = texture(seabed_mask, uv).r;
		}
	}

	// In Godot's reverse-Z buffer, the cleared far depth is zero.
	if (raw_depth > 0.0 && coverage > 0.0) {
		vec3 ground_view = view_space_position(SCREEN_UV, raw_depth, INV_PROJECTION_MATRIX);
		ground_position = (INV_VIEW_MATRIX * vec4(ground_view, 1.0)).xyz;
		float water_column = water_position.y - ground_position.y;
		has_seabed = ground_view.z < VERTEX.z && water_column >= 0.0;
		if (has_seabed) {
			vertical_depth = water_column;
			optical_depth = length(ground_view - VERTEX);
		}
	}

	float opacity = 1.0;
	vec3 tint = deep_color.rgb;
	float shoreline_foam = 0.0;
	float caustics = 0.0;
	if (has_seabed) {
		float fade = smoothstep(0.0, visibility_depth, optical_depth);
		tint = mix(deep_color.rgb, shallow_color.rgb, (1.0 - fade) * coverage);
		float light_through = exp(-absorption * optical_depth) * (1.0 - fade) * coverage;
		opacity = 1.0 - 0.92 * light_through;

		vec2 foam_uv = water_position.xz * 2.2 + vec2(TIME * 0.21, -TIME * 0.12);
		float foam_noise = value_noise(foam_uv) * 0.73 + value_noise(foam_uv * 2.17) * 0.27;
		float edge = vertical_depth / max(0.01, foam_width);
		float foam_shape = 1.0 - smoothstep(0.38, 1.15, edge + foam_noise * 0.55);
		shoreline_foam = foam_shape * smoothstep(0.29, 0.63, foam_noise) * coverage;

		vec2 bed_uv = ground_position.xz * 3.6;
		float light_phase = sin(bed_uv.x + sin(bed_uv.y - TIME * 0.77))
			* sin(bed_uv.y - sin(bed_uv.x + TIME * 0.64));
		caustics = smoothstep(0.64, 0.99, abs(light_phase)) * light_through * 0.16
			* smoothstep(0.05, 0.24, vertical_depth);
	}

	vec2 xz = water_position.xz;
	float ripple_a = dot(xz, vec2(3.8, 2.4)) - TIME * 1.46;
	float ripple_b = dot(xz, vec2(-2.8, 5.0)) + TIME * 1.19;
	vec2 slope = wave_height * (
		SWELL_A * 0.66 * cos(dot(xz, SWELL_A) - TIME * wave_speed)
		+ SWELL_B * 0.34 * cos(dot(xz, SWELL_B) - TIME * wave_speed * 1.46)
	);
	slope += surface_detail * (vec2(0.077, 0.055) * cos(ripple_a) + vec2(-0.048, 0.069) * cos(ripple_b));
	NORMAL = normalize(mat3(VIEW_MATRIX) * vec3(-slope.x, 1.0, -slope.y));

	float glint = (sin(ripple_a) * sin(ripple_b) * 0.5 + 0.5) * surface_detail;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	tint = mix(tint * (0.94 + 0.09 * glint), foam_color.rgb, shoreline_foam);
	ALBEDO = tint;
	EMISSION = tint * (0.075 + 0.055 * fresnel) + shallow_color.rgb * caustics;
	ALPHA = max(opacity, shoreline_foam * 0.96);
	ROUGHNESS = mix(0.25, 0.64, shoreline_foam);
	SPECULAR = mix(0.46, 0.21, shoreline_foam);
}
