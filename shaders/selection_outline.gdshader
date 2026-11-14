// The selected item's outline (Grayson 2026-11-14): an inverted hull. The
// mesh's back faces are drawn pushed outward along their normals, in a solid
// colour, so a band shows around the silhouette. The push is in screen space,
// so the line is the same number of pixels thick near and far, and in the
// orthographic view. LevelView feeds it a copy of the mesh with smoothed
// normals, so boxes and stairs don't split at their corners.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Thickness in pixels.
uniform float width = 3.0;

void vertex() {
  vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
  vec3 view_normal = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
  vec2 push = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
  if (length(push) > 0.0001) {
    clip.xy += normalize(push) * width * 2.0 / VIEWPORT_SIZE * clip.w;
  }
  POSITION = clip;
}

void fragment() {
  ALBEDO = outline_color.rgb;
}
