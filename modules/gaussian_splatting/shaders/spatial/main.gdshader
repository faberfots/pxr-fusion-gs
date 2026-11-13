shader_type spatial;
render_mode unshaded, fog_disabled, blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D render_texture : filter_linear;
uniform bool integrated_frame = false;
uniform float exposure : hint_range(0.0,5.0)=1.0;
uniform float contrast : hint_range(0.5,2.0)=1.0;
uniform float saturation : hint_range(0.0,2.0)=1.0;
uniform float sharpness : hint_range(0.0,1.0)=0.0;
uniform float black_point : hint_range(0.0,0.5)=0.0;
uniform float white_point : hint_range(0.5,2.0)=1.0;
uniform float temperature : hint_range(-1.0,1.0)=0.0;
uniform vec3 tint : source_color=vec3(1.0);
vec3 straight_color(vec4 sample_color) {
	return sample_color.a>0.00001?sample_color.rgb/sample_color.a:vec3(0.0);
}
void vertex() {
	POSITION=vec4(VERTEX.xy,1.0,1.0);
}
void fragment() {
	vec4 sample_color=texture(render_texture,SCREEN_UV);
	vec3 color=straight_color(sample_color);
	if(integrated_frame) {
		ALBEDO=max(color,vec3(0.0));
		ALPHA=sample_color.a;
	} else {
	if(sharpness>0.0 && sample_color.a>0.001) {
		vec2 step_uv=1.0/vec2(textureSize(render_texture,0));
		vec3 neighborhood=straight_color(texture(render_texture,SCREEN_UV+vec2(step_uv.x,0.0)));
		neighborhood+=straight_color(texture(render_texture,SCREEN_UV-vec2(step_uv.x,0.0)));
		neighborhood+=straight_color(texture(render_texture,SCREEN_UV+vec2(0.0,step_uv.y)));
		neighborhood+=straight_color(texture(render_texture,SCREEN_UV-vec2(0.0,step_uv.y)));
		color+=sharpness*(color-neighborhood*0.25);
	}
	color=max(vec3(0.0),(color-black_point)/max(white_point-black_point,0.001));
	color*=exposure;
	color=mix(vec3(0.18),color,contrast);
	float gray=dot(color,vec3(0.2126,0.7152,0.0722));
	color=mix(vec3(gray),color,saturation);
	color=(color+temperature*vec3(0.08,0.02,-0.08))*tint;
	// Compute output is linear and premultiplied. Recover straight color once; Godot owns tone mapping.
	ALBEDO=max(color,vec3(0.0));
	ALPHA=sample_color.a;
	}
}
