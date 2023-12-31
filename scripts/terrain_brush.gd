var script_class = "tool"

# Script constants
# TODO: Add support for multiple biome presets in the future
const BIOMES_PATH: String = "user://default.dungeondraft_biomes"
const DEFAULT_BIOMES: String = "res://data/default.dungeondraft_biomes"
# HACK: Would probably be better to save this stuff in the map files themselves,
# but the risk of incompatibilty is... extreme to say the least

# TODO: Move this into another class
const USER_DATA: String = "user://terrain_presets.json"

# Script verbosity mode:
# INFO = All logging messages printed
# WARN = Only warnings and above are printed
# ERROR = Only errors are printed
enum VERBOSITY {
    INFO,
    WARN,
    ERROR
}

const DEBUG_MODE = VERBOSITY.WARN

# Predefined Globals
var terrain_brush
var terrain_list
var terrain_buttons
var biome_dropdown
var expand_slots

func init_globals():
    # WARNING: Call at the start of script and ONLY ONCE
    terrain_brush = Global.Editor.Toolset.ToolPanels["TerrainBrush"]
    # TODO: Replace magic numbers in get_child with proper node ids
    terrain_list = terrain_brush.Align.get_child(7).get_child(0)
    terrain_buttons = terrain_brush.Align.get_child(7).get_child(1).get_children()
    biome_dropdown = terrain_brush.Align.get_child(6)
    expand_slots = terrain_brush.Align.get_child(10)

# Script Globals
# Biome dictionary
var biomes: Dictionary

# User settings dictionary
var user_data: Dictionary

# Script entry point
func start():
    log_info("Loading terrain presets...")

    # Initialize global variables, must be called before any other functions!
    init_globals()

    # HACK: Override the normal biome_dropdown signal here. Currently it is 
    # not possible to interact in any meaningful way with the in-built biome
    # dictionary, as it is not a generic dictionary. As such, when choosing 
    # a new biome, the normal biome dictionary is ignored, and the local
    # one replaces it.
    var conns = biome_dropdown.get_signal_connection_list("item_selected")
    biome_dropdown.disconnect("item_selected", conns[0].target, conns[0].method)
    biome_dropdown.connect("item_selected", self, "set_biome")
    
    for i in range(0, len(terrain_buttons)):
        conns = terrain_buttons[i].get_signal_connection_list("pressed")
        terrain_buttons[i].disconnect("pressed", conns[0].target, conns[0].method)
        terrain_buttons[i].connect("pressed", self, "popup_terrain_window", [i])
    
    # HACK: Overriding the 'pressed' signal for the expand_slots button
    conns = expand_slots.get_signal_connection_list("toggled")
    expand_slots.disconnect("toggled", conns[0].target, conns[0].method)
    expand_slots.connect("toggled", self, "expand")

    # HACK: Disconnecting undefined method from 'about_to_show' signal, this 
    # was throwing an error message, and I'm not entirely sure why :/
    Global.Editor.TerrainWindow.disconnect("about_to_show", Global.Editor.TerrainWindow, "_on_TerrainWindow_about_to_show")

    Global.Editor.TerrainWindow.connect("popup_hide", self, "sync_biome")

    # Load user data
    if load_user_data() != 0:
        log_err("Some sort of error when loading user data!")

    # Load biomes into biomes dictionary, then override
    # the default biomes terrain set with our own
    if load_biomes() != 0:
        log_err("Some sort of error when loading biomes!")

    # TODO (🤔): Maybe move this into its own function 
    # Setup terrain preset buttons
    var new_button = terrain_brush.CreateButton("New Biome", Global.Root + "icons/new-shoot.png")
    new_button.connect("pressed", self, "new_biome_window")
    terrain_brush.Align.move_child(new_button, 6)

    var del_button = terrain_brush.CreateButton("Delete Biome", Global.Root + "icons/trash-can.png")
    del_button.connect("pressed", self, "del_biome")
    terrain_brush.Align.move_child(del_button, 7)

    var save_button = terrain_brush.CreateButton("Save Biomes", Global.Root + "icons/save.png")
    save_button.connect("pressed", self, "save_biomes")
    save_button.hint_tooltip = "WARNING: This will overwrite your current preset file"
    terrain_brush.Align.move_child(save_button, 8)

    var load_button = terrain_brush.CreateButton("Reload Biomes", Global.Root + "icons/load.png")
    load_button.connect("pressed", self, "load_biomes")
    terrain_brush.Align.move_child(load_button, 9)

    # TODO: New function?
    # Add popups and windows
    var biome_window = load(Global.Root + "scenes/NewBiomeWindow.tscn").instance()
    biome_window.name = "NewBiomeWindow"
    biome_window.get_node("Margins/VAlign/Buttons/OkayButton").connect("pressed", self, "add_biome", [biome_window])
    Global.Editor.get_node("Windows").add_child(biome_window, true)
    
    
# Utilities
  
func add_biome(biome_window):
    # Hide popup
    biome_window.hide()

    # Add new biome to biomes dictionary
    # TODO: Add warning dialog if overwriting existing biome save
    var biome_name = biome_window.get_node("Margins/VAlign/Label/LabelLineEdit").text
    if not biome_name or len(biome_name) <= 0:
        log_warn("Invalid or empty biome name!")
        Global.Editor.Warn("Warning!", "Invalid or empty biome name!")
        return 

    log_info("Adding new biome " + biome_name)

    # Setting default textures to dirt for now...
    biomes[biome_name] = [
        "res://textures/terrain/terrain_dirt.png", 
        "res://textures/terrain/terrain_dirt.png", 
        "res://textures/terrain/terrain_dirt.png", 
        "res://textures/terrain/terrain_dirt.png"
    ]

    update_biomes()
    set_biome(biome_dropdown.get_item_count() - 1)

func del_biome():
    # If biome is the last biome in the dict, lets not delete it eh?
    if biomes.keys().size() <= 1:
        log_warn("Must have at least 1 biome!")
        Global.Editor.Warn("Warning!", "Must have at least 1 biome!")
        return
        
    # Get currently selected biome
    var cur_biome = biome_dropdown.text

    # Remove biome from biomes dict
    if not biomes.erase(cur_biome):
        log_warn("Biome " + cur_biome + " not found in biomes!")

    update_biomes()
    set_biome(0)

# Save current biomes state to preset file
func save_biomes():
    # Prompt for confirmation if file already exists
    var file = File.new()
    if file.file_exists(BIOMES_PATH):
        # HACK: Slight hack, guessing this is the proper confirm node?
        var save_confirm = Global.Editor.get_node("Windows/Confirm")
        save_confirm.dialog_text = "WARNING: This will overwrite your current biome preset, are you sure?"
        if (!save_confirm.get_ok().is_connected("pressed", self, "_save_confirmed")):
            save_confirm.get_ok().connect("pressed", self, "_save_confirmed")
            save_confirm.get_cancel().connect("pressed", self, "_save_cancelled")
        save_confirm.popup_centered_clamped()
    else: 
        _save_confirmed()
    

func _save_confirmed():
    log_info("Saving file " + BIOMES_PATH + "...")
    var file = File.new()
    file.open(BIOMES_PATH, File.WRITE)
    file.store_line(JSON.print(biomes, "\t"))
    file.close()

func _save_cancelled():
    log_info("Save cancelled")

func load_user_data() -> int:
    log_info("Loading user data...")

    # Populate user data dictionaries
    var file = File.new()
    file.open(USER_DATA, File.READ)
    var line = file.get_as_text()
    user_data = JSON.parse(line).result
    file.close()

    if not user_data:
        log_warn("Failed to load user data " + USER_DATA + ", file is either missing or corrupted")
        log_info("Initializing default user data dictionary... at " + USER_DATA)
        file = File.new()
        file.open(USER_DATA, File.WRITE)
        # TODO: Move this out of here, temporary location
        user_data = {"maps": {}}
        file.store_line(JSON.print(user_data, "\t"))
        file.close()

    return 0

func load_biomes() -> int:
    log_info("Loading biomes...")

    # Save last biome selected
    var last_biome = biome_dropdown.text

    # Populate biomes
    var file = File.new()   
    file.open(BIOMES_PATH, File.READ)
    var line = file.get_as_text()
    biomes = JSON.parse(line).result
    file.close()

    if not biomes:
        log_warn("Failed to load preset " + BIOMES_PATH + ", file is either missing or corrupted")
        log_info("Initializing default biomes preset at " + DEFAULT_BIOMES)
        file.open(DEFAULT_BIOMES, File.READ)
        line = file.get_as_text()
        biomes = JSON.parse(line).result
        file.close()
        save_biomes()
        
    update_biomes()

    # If the last selected biome still exists, select it
    var last_biome_idx = biomes.keys().find(last_biome)
    if last_biome_idx != -1:
        set_biome(last_biome_idx)
    else: 
        set_biome(0)
    return 0 

func update_biomes():
    log_info("Updating biomes...")
    biome_dropdown.clear()
    for biome in biomes.keys():
        biome_dropdown.add_item(biome)

func expand(value):
    log_info("Expanded slots button pressed")
    # Ensure this is called before updating the buttons
    terrain_brush.Tool.ExpandSlots(value)

    # TODO: Is there a better way to do this?
    # Currently just getting the newly created buttons, then overriding them
    # Notably this is 11 as it is after the terrain brush buttons are added
    terrain_buttons = terrain_brush.Align.get_child(11).get_child(1).get_children()
    for i in range(0, len(terrain_buttons)):
        var conns = terrain_buttons[i].get_signal_connection_list("pressed")
        terrain_buttons[i].disconnect("pressed", conns[0].target, conns[0].method)
        terrain_buttons[i].connect("pressed", self, "popup_terrain_window", [i])

    set_biome(biome_dropdown.selected)
    sync_biome()

func set_biome(index):
    var biome_name = biome_dropdown.get_item_text(index)
    log_info("Setting biome to " + biome_name)
    biome_dropdown.select(index)
    
    # Only pop up accept dialog once
    var clean = true
    var len_textures = 4

    # If terrain list has been expanded, lazily attempt to load expanded preset
    if (Global.World.Level.Terrain.ExpandedSlots):
        len_textures = 8
        if len(biomes[biome_name]) < 8:
            log_info("Appending default terrain")
            biomes[biome_name] += [
                "res://textures/terrain/terrain_dirt.png", 
                "res://textures/terrain/terrain_dirt.png", 
                "res://textures/terrain/terrain_dirt.png", 
                "res://textures/terrain/terrain_dirt.png"
            ]
    
    # Load textures
    for i in range(0, len_textures):
        var texture = load_texture(biomes[biome_name][i])
        if texture:
            Global.World.Level.Terrain.SetTexture(texture, i)
            terrain_list.set_item_icon(i, texture)
            terrain_list.set_item_text(i, parse_resource_name(texture))
        else:
            clean = false
    if not clean:
        log_err("Some kind of error when attempting to load biome " + biome_name 
        + ".\nPlease check that all asset packs are properly loaded!")

        Global.Editor.Warn("Alert!", "Some kind of error when attempting to load biome " + biome_name 
        + ".\nPlease check that all asset packs are properly loaded!")


func sync_biome():
    # Sync currently set biome with terrain list
    var cur_biome = biome_dropdown.text
    log_info("Updating biome " + cur_biome)

    var len_terrains = 4
    if Global.World.Level.Terrain.ExpandedSlots:
        len_terrains = 8

    for i in range(0, len_terrains):
        biomes[cur_biome][i] = Global.World.Level.Terrain.GetTexture(i).resource_path    

func load_texture(texture_path):
    # TODO: Detect if the asset pack is loaded or not before deciding
    # to load the terrain. The current behavior is that the texture 
    # will be loaded whether the pack is loaded or not. This is
    # unexpected behavior, and can lead to some frustrating debugging
    log_info("Loading texture " + texture_path)
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

# Popups and windows
func new_biome_window():
    # Popup new biome dialog
    var biome_menu =  Global.Editor.get_node("Windows/NewBiomeWindow")
    biome_menu.popup_centered()

func popup_terrain_window(index):
    # HACK: Wrapper function around the open terrain window buttons
    # Currently it seems like the TerrainWindow is not properly emitting
    # the popup_hide signal. I could just call popup directly, but 
    # investigation reveals that the window is doing some background stuff
    # to set the grid menu thing...
    # Thus this wrapper forces the window to 'Open' briefly, 
    # hides it immediately, then popup immediately after to force the signal to trigger
    log_info("Terrain window popped up")
    var terrain_window = Global.Editor.TerrainWindow
    terrain_window.Open(index)
    terrain_window.hide()
    terrain_window.popup()

# Logging utilities, adjusted based on verbosity of script
func log_info(msg):
    if DEBUG_MODE != VERBOSITY.WARN and DEBUG_MODE != VERBOSITY.ERROR:
        print("[terrain-presets] INFO: " + msg)

func log_warn(msg):
    if DEBUG_MODE != VERBOSITY.ERROR:
        print("[terrain-presets] WARN: " + msg)

func log_err(msg):
    print("[terrain-presets] ERR: " + msg)