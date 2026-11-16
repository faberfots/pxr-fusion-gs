shader_type spatial;
render_mode blend_mix, depth_draw_never;
// A guide background: never cover an opaque scene surface, even below the grid.
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D grid_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 grid_position;
varying vec3 grid_normal;
void vertex() {
	grid_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	grid_normal=MODEL_NORMAL_MATRIX*NORMAL;
}
void fragment() {
	if(textureLod(scene_depth,SCREEN_UV,0.0).r>0.0)discard;
	vec3 weights=pow(abs(normalize(grid_normal)),vec3(16.0));
	weights/=max(dot(weights,vec3(1.0)),0.00001);
	vec3 color=texture(grid_texture,grid_position.zy).rgb*weights.x;
	color+=texture(grid_texture,grid_position.xz).rgb*weights.y;
	color+=texture(grid_texture,grid_position.xy).rgb*weights.z;
	ALBEDO=color;ROUGHNESS=1.0;ALPHA=1.0;
}
