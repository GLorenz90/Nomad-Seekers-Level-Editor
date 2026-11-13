class_name LevelMaterials
extends RefCounted
## Materials of a level (format 2, map.materials), shared by the game and the
## level editor so a material looks the same in both.
##
##   {"id": "mossy_stone", "name": "Mossy stone", "folder": "Stone",
##    "mapping": "world", "tile": 2.0,
##    "albedo": "assets/mossy_stone.png", "color": [1, 1, 1], "opacity": 1.0,
##    "transparency": "none", "alpha_cutoff": 0.5,
##    "normal": "assets/mossy_stone_n.png", "normal_strength": 1.0,
##    "roughness": 1.0, "roughness_map": "assets/mossy_stone_orm.png", "roughness_channel": "green",
##    "metallic": 0.0, "metallic_map": "", "metallic_channel": "blue",
##    "ao_map": "assets/mossy_stone_orm.png", "ao_channel": "red", "ao_strength": 1.0,
##    "emission": [0, 0, 0], "emission_energy": 1.0, "emission_map": "",
##    "height_map": "", "height_scale": 5.0}
##
## Every key but "id" is optional.
##
## Mapping:
##   "world" (the default): images are projected in world space (triplanar),
##     "tile" metres per repeat, so a texture keeps its scale on a shape of any
##     size: a 2 m stone texture looks the same on a 1 m step and a 40 m floor.
##   "uv": the mesh's own UVs, repeated "uv_repeat" times. Right for a
##     model's own (unwrapped) textures, and needed for height maps, which
##     Godot can't draw with triplanar mapping.
##
## Maps: "roughness_map", "metallic_map" and "ao_map" read one channel
## (`*_channel`: red, green, blue, alpha or gray). glTF packs occlusion,
## roughness and metallic into one image (red, green, blue), so the same file
## can be used for all three. "roughness" and "metallic" multiply their map.
## Transparency: "none", "alpha" (blended, using the colour image's alpha
## times "opacity") or "cutout" (pixels below "alpha_cutoff" are dropped;
## leaves, fences). Images must be .png / .jpg / .webp files inside the level
## folder (LevelData.safe_file).

const CHANNELS := {
	"red": BaseMaterial3D.TEXTURE_CHANNEL_RED, "green": BaseMaterial3D.TEXTURE_CHANNEL_GREEN,
	"blue": BaseMaterial3D.TEXTURE_CHANNEL_BLUE, "alpha": BaseMaterial3D.TEXTURE_CHANNEL_ALPHA,
	"gray": BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE}
const MAPPINGS := ["world", "uv"]
const TRANSPARENCY := ["none", "alpha", "cutout"]

static var _textures := {}
static var _materials := {}


## The material for an id (null if the level has none by that name).
static func build(level: LevelData, id: String) -> StandardMaterial3D:
	var spec := level.find_material(id)
	if spec.is_empty():
		return null
	var key := level.dir + "|" + id + "|" + str(spec.hash())
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Colour and transparency.
	var tint := LevelData.vec3(spec.get("color"), Vector3.ONE)
	var opacity := clampf(float(spec.get("opacity", 1.0)), 0.0, 1.0)
	mat.albedo_color = Color(clampf(tint.x, 0, 1), clampf(tint.y, 0, 1), clampf(tint.z, 0, 1), opacity)
	var albedo := texture(level, String(spec.get("albedo", "")))
	if albedo:
		mat.albedo_texture = albedo
	match String(spec.get("transparency", "none")):
		"alpha":
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		"cutout":
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.alpha_scissor_threshold = clampf(float(spec.get("alpha_cutoff", 0.5)), 0.0, 1.0)
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # leaves are seen from both sides
	# Surface.
	var normal := texture(level, String(spec.get("normal", "")))
	if normal:
		mat.normal_enabled = true
		mat.normal_texture = normal
		mat.normal_scale = clampf(float(spec.get("normal_strength", 1.0)), 0.0, 4.0)
	mat.roughness = clampf(float(spec.get("roughness", 0.85)), 0.0, 1.0)
	var rough := texture(level, String(spec.get("roughness_map", "")))
	if rough:
		mat.roughness_texture = rough
		mat.roughness_texture_channel = channel(spec, "roughness_channel")
	mat.metallic = clampf(float(spec.get("metallic", 0.0)), 0.0, 1.0)
	var metal := texture(level, String(spec.get("metallic_map", "")))
	if metal:
		mat.metallic_texture = metal
		mat.metallic_texture_channel = channel(spec, "metallic_channel")
	var ao := texture(level, String(spec.get("ao_map", "")))
	if ao:
		mat.ao_enabled = true
		mat.ao_texture = ao
		mat.ao_texture_channel = channel(spec, "ao_channel")
		mat.ao_light_affect = clampf(float(spec.get("ao_strength", 1.0)), 0.0, 1.0)
	# Glow.
	var glow := LevelData.vec3(spec.get("emission"), Vector3.ZERO)
	var glow_map := texture(level, String(spec.get("emission_map", "")))
	if glow_map or glow.length_squared() > 0.0:
		mat.emission_enabled = true
		# With a map and no colour, the map glows in its own colours.
		mat.emission = Color(clampf(glow.x, 0, 1), clampf(glow.y, 0, 1), clampf(glow.z, 0, 1)) if glow.length_squared() > 0.0 else Color.WHITE
		mat.emission_energy_multiplier = clampf(float(spec.get("emission_energy", 1.0)), 0.0, 16.0)
		if glow_map:
			mat.emission_texture = glow_map
	# Mapping (and height, which needs UVs).
	if String(spec.get("mapping", "world")) == "uv":
		var repeat := clampf(float(spec.get("uv_repeat", 1.0)), 0.01, 100.0)
		mat.uv1_scale = Vector3(repeat, repeat, 1.0)
		var height := texture(level, String(spec.get("height_map", "")))
		if height:
			mat.heightmap_enabled = true
			mat.heightmap_texture = height
			mat.heightmap_scale = clampf(float(spec.get("height_scale", 5.0)), 0.0, 16.0)
			mat.heightmap_deep_parallax = true
	else:
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3.ONE / clampf(float(spec.get("tile", 2.0)), 0.1, 100.0)
	if _materials.size() > 256:
		_materials.clear()
	_materials[key] = mat
	return mat


static func channel(spec: Dictionary, key: String) -> BaseMaterial3D.TextureChannel:
	return CHANNELS.get(String(spec.get(key, "gray")), BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE)


## The channel name for a Godot texture channel.
static func channel_name(value: int) -> String:
	for k in CHANNELS:
		if CHANNELS[k] == value:
			return k
	return "gray"


## An image from the level folder as a texture (null if missing or not allowed).
static func texture(level: LevelData, file: String) -> Texture2D:
	if not LevelData.safe_file(file, LevelData.TEXTURE_FILES):
		return null
	var path := level.dir.path_join(file)
	if _textures.has(path):
		return _textures[path]
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	image.generate_mipmaps()
	var tex := ImageTexture.create_from_image(image)
	_textures[path] = tex
	return tex


## Forget loaded images (after one is replaced on disk).
static func clear_cache() -> void:
	_textures.clear()
	_materials.clear()
