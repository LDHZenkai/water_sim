// Same vertices/displacement as production. Bands expose all four skirt edges.
void fragment() {
 // QUEUE
 vec3 local=(world_to_ship*vec4(world_position,1)).xyz;
 // HULL_CLIP
 float r = max(abs(grid_coordinate.x), abs(grid_coordinate.y));
 vec3 color = vec3(0.15, 0.7, 0.25);
 if(r >= 200.0) color = vec3(0.8, 0.8, 0.1);
 if(r >= 400.0) color = vec3(0.1, 0.65, 0.9);
 if(r >= 800.0) color = vec3(0.9, 0.3, 0.15);
 if(r >= 1600.0) color = vec3(0.7, 0.15, 0.8);
 if(r >= 3000.0) color = vec3(0.2, 0.25, 0.7);
 ALBEDO = color;
 EMISSION = vec3(0.0);
 ROUGHNESS = 1.0;
}
