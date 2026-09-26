// Shared linear horizon radiance: retain azimuth colour without HDR sun energy.
vec3 horizon_radiance(vec3 sample_color) {
 float luminance=max(dot(sample_color,vec3(0.2126,0.7152,0.0722)),0.001);
 return vec3(0.45,0.42,0.38)*mix(vec3(1.0),clamp(sample_color/luminance,vec3(0.5),vec3(1.5)),0.3);
}
