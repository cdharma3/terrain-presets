var script_class = "tool"

# Globals
var terrain_brush
var terrain_list
var biome_dropdown
# HACK: Reference to Master node, needed because 
# it is not exposed in the modding api directly
var Master: Node

# Script constants
# TODO: Add support for multiple biome presets in the future
const BIOMES_PATH: String = "user://preset1.dungeondraft_biomes"

func init_globals():
    Master = Global.Editor.get_parent()
    terrain_brush = Global.Editor.Toolset.ToolPanels["TerrainBrush"]
    terrain_list = terrain_brush.Align.get_node(7).get_child(0)
    biome_dropdown = terrain_brush.Align.get_child(6)

# Biome dictionary
var biomes: Dictionary

# Script entry point
func start():
    # Initialize global variables, must be called before any other functions!
    init_globals()

    # Override signals
    var conns = biome_dropdown.get_signal_connection_list("item_selected")
    biome_dropdown.disconnect("item_selected", conns[0].target, conns[0].method)
    biome_dropdown.connect("item_selected", self, "set_biome")

    # Load biomes into biomes dictionary, then override
    # the default biomes terrain set with our own
    if load_biomes() != 0:
        log_err("Some sort of error when loading biomes!")

    # Setup terrain preset buttons
    var save_button = terrain_brush.CreateButton("Save Biomes", "res://ui/icons/menu/save.png")
    save_button.connect("pressed", self, "save_biomes")
    save_button.hint_tooltip = "WARNING: This will overwrite your current preset file"
    terrain_brush.Align.move_child(save_button, 6)

    var load_button = terrain_brush.CreateButton("Load Biomes", "res://ui/icons/menu/redo.png")
    load_button.connect("pressed", self, "load_biomes")
    terrain_brush.Align.move_child(load_button, 7)

    
# Utilities

func save_biomes(): 
    # Save current biomes state to preset

    pass

func load_biomes() -> int:
    log_info("Loading terrain presets...")

    # Populate biomes
    var file = File.new()
    file.open(BIOMES_PATH, File.READ)
    var line = file.get_as_text()
    biomes = JSON.parse(line).result
    file.close()

    if not biomes:
        log_err("Failed to load preset " + BIOMES_PATH)
        return -1

    # Override biome dropdown to link into script
    log_info("Loading biomes...")
    biome_dropdown.clear()
    for biome in biomes.keys():
        biome_dropdown.add_item(biome)
    set_biome(0)
    return 0

func set_biome(index):
    log_info("Setting biome to " + biomes.keys()[index])

    var textures = biomes[biomes.keys()[index]]
    for i in range(0, len(textures)):
        var texture = load_texture(textures[i])
        Global.World.Level.Terrain.SetTexture(texture, i)
        terrain_list.set_item_icon(i, texture)
        terrain_list.set_item_text(i, parse_resource_name(texture))
    

func load_texture(texture_path):
    log_info("Loading texture " + texture_path + "...")
    if ResourceLoader.exists(texture_path):
        return ResourceLoader.load(texture_path)
    
    var image = Image.new()
    if image.load(texture_path) != 0:
        log_err(texture_path + " not found!")
        return null

    var image_texture = ImageTexture.new()
    image_texture.create_from_image(image)
    image_texture.resource_path = texture_path
    return image_texture

func parse_resource_name(resource) -> String:
    return resource.resource_path.split("/")[-1].split(".")[0].capitalize()

# Logging utilities
func log_info(msg):
    print("[terrain-presets] INFO: " + msg)

func log_warn(msg):
    print("[terrain-presets] WARN: " + msg)

func log_err(msg):
    print("[terrain-presets] ERR: " + msg)