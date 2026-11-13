class_name LevelMaterials
extends RefCounted
## Materials of a level (format 2, map.materials), shared by the game and the
## level editor so a material looks the same in both.
##
##   {"id": "mossy_stone", "name": "Mossy stone", "albedo": "assets/mossy_stone.png",
##    "normal": "assets/mossy_stone_n.png", "normal_strength": 1.0, "color": [1, 1, 1],
##    "roughness": 0.9, "metallic": 0.0, "tile": 2.0, "license": "CC0", "author": "",
##    "folder": "Stone"}
##
## Images are projected in world space (triplanar), "tile" metres per repeat,
## so a texture keeps its scale on a shape of any size or shape: a 2 m stone
## texture looks the same on a 1 m step and a 40 m floor. Images must be
## .png / .jpg / .webp files inside the level folder (LevelData.safe_file).

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
	var tint := LevelData.vec3(spec.get("color"), Vector3.ONE)
	mat.albedo_color = Color(clampf(tint.x, 0, 1), clampf(tint.y, 0, 1), clampf(tint.z, 0, 1))
	mat.roughness = clampf(float(spec.get("roughness", 0.85)), 0.0, 1.0)
	mat.metallic = clampf(float(spec.get("metallic", 0.0)), 0.0, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var albedo := texture(level, String(spec.get("albedo", "")))
	if albedo:
		mat.albedo_texture = albedo
	var normal := texture(level, String(spec.get("normal", "")))
	if normal:
		mat.normal_enabled = true
		mat.normal_texture = normal
		mat.normal_scale = clampf(float(spec.get("normal_strength", 1.0)), 0.0, 4.0)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / clampf(float(spec.get("tile", 2.0)), 0.1, 100.0)
	if _materials.size() > 256:
		_materials.clear()
	_materials[key] = mat
	return mat


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
