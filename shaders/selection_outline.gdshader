// The selected item's outline (Grayson 2026-11-14). A copy of each mesh is
// pushed outward along its normals and drawn in a solid colour, but only where
// the stencil mask (selection_mask.gdshader) didn't mark the item itself, so
// what's left is a band round its silhouette. It draws through other things,
// so a piece sunk in the floor or behind a wall still shows where it is. The
// push is in screen space: the same number of pixels near and far, and in the
// orthographic view. LevelView feeds it a copy of the mesh with smoothed
// normals, so boxes and stairs don't split at their corners.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
stencil_mode read, compare_not_equal, 1;

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
  ALPHA = outline_color.a;
}
