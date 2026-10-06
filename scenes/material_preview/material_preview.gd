extends Node3D
## Run this scene (F6). Capture with -- --capture; variants with --variant.

func _ready() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("202833")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("bbc9df")
	environment.ambient_light_energy = 0.45
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-28,0)
	sun.light_color = Color("ffecd5")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)
	var asphalt := load("res://assets/materials/painterly/asphalt.tres").duplicate() as ShaderMaterial
	var brick := load("res://assets/materials/painterly/brick.tres").duplicate() as ShaderMaterial
	var args := OS.get_cmdline_user_args()
	if "--variant" in args:
		asphalt.set_shader_parameter("base_color",Color("33312d"))
		asphalt.set_shader_parameter("brush_strength",1.0)
		asphalt.set_shader_parameter("seed",41.0)
		brick.set_shader_parameter("brick_color",Color("565e69"))
		brick.set_shader_parameter("light_color",Color("a1a6ac"))
		brick.set_shader_parameter("mortar_width",0.2)
		brick.set_shader_parameter("edge_wear",1.0)
		brick.set_shader_parameter("seed",31.0)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(10,8)
	add_mesh(floor_mesh,asphalt,Vector3.ZERO)
	var wall := BoxMesh.new()
	wall.size = Vector3(8,3.5,0.4)
	add_mesh(wall,brick,Vector3(0,1.75,-2.4))
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(8,7.4,11)
	camera.look_at(Vector3(0,0.8,-0.2))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.8
	camera.current = true
	var ui := CanvasLayer.new()
	add_child(ui)
	var title := Label.new()
	title.text = "PAINTERLY / CEL MATERIAL STUDY"
	title.position = Vector2(36,28)
	title.add_theme_font_size_override("font_size",28)
	ui.add_child(title)
	var caption := Label.new()
	caption.text = "01  BLUE-GRAY ASPHALT     /     02  TERRACOTTA BRICK\nProcedural paint • stepped light • editable palettes"
	caption.position = Vector2(36,72)
	caption.add_theme_font_size_override("font_size",18)
	ui.add_child(caption)
	if "--capture" in args:
		for frame in range(12):
			await RenderingServer.frame_post_draw
		var suffix := "variant" if "--variant" in args else "preview"
		var output := "res://assets/materials/painterly/" + suffix + ".png"
		var result := get_viewport().get_texture().get_image().save_png(output)
		print("Material capture: ",output," result=",result)
		get_tree().quit(result)

func add_mesh(mesh: Mesh, material: Material, location: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = location
	add_child(instance)
