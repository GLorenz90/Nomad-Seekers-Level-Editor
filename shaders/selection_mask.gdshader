// The first half of the selection outline (Grayson 2026-11-14): marks the
// selected item's pixels in the stencil buffer and draws nothing, so the
// outline hull (selection_outline.gdshader) is only drawn around it, never
// over it. Works for open, one-sided meshes, which a plain inverted hull fills
// in white.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
stencil_mode write, compare_always, 1;

void fragment() {
  ALBEDO = vec3(0.0);
  ALPHA = 0.0;
}
