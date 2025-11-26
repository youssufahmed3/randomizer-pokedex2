extends Node2D

# --- Public Exported Variables (UI State) ---
@export var is_log_loaded: bool = false : set = set_is_log_loaded
# NEW: Holds the details of the last selected Pokémon.
var loaded_pokemon: Dictionary = {}

# --- Private Variables ---
# Dictionary to store all randomized Pokémon data.
var randomized_pokedex = {}
const POKEMON_SPRITE_BASE_URL = "https://img.pokemondb.net/sprites/black-white/normal/"

# Lerp constant for smooth progress bar animation
const BAR_LERP_SPEED = 0.1
# Maximum possible stat value for progress bar calculation (Standard max base stat in core games is 255)
const MAX_BASE_STAT = 255

# --- Node References (Must match your scene structure) ---
@onready var file_dialog = $FileDialog
@onready var load_button = $LoadButton
@onready var sprite = $Sprite2D
@onready var image_loader = $HTTPRequest
@onready var file_path_label = $FilePathLabel
@onready var search_line_edit = $SearchLineEdit
@onready var results_list = $SearchResultsList

@onready var typeLabel = $TypeLabel
@onready var abilityLabel = $AbilityLabel

@onready var hplabel = $HPLabel
@onready var atklabel = $AttackLabel
@onready var deflabel = $DefenseLabel
@onready var spalabel = $SpAttackLabel
@onready var specialdefenselabel = $SpDefenseLabel
@onready var speedlabel = $SpeedLabel

@onready var hpbar = $ProgressBar
@onready var atkbar = $ProgressBar2
@onready var defbar = $ProgressBar3
@onready var spabar = $ProgressBar4
@onready var specialdefensebar = $ProgressBar5
@onready var speedbar = $ProgressBar6

# Temporary targets for lerping (used in _process)
var target_stats: Dictionary = {
	"hp": 0, "atk": 0, "def": 0, "spatk": 0, "spdef": 0, "spd": 0
}


# --- Initialization ---
func _ready():
	# CRITICAL VALIDATION: Check if essential nodes were loaded successfully
	if not is_instance_valid(results_list):
		printerr("ERROR: $SearchResultsList node path is incorrect or the node is missing in the scene tree! Check your scene tree.")
		return # Stop execution if the list node isn't found
	
	if not is_instance_valid(image_loader):
		printerr("ERROR: $HTTPRequest (ImageLoader) node path is incorrect or missing. Image loading will fail!")
		
	if is_instance_valid(image_loader):
		# Connect the signal for asynchronous image loading
		image_loader.request_completed.connect(_on_http_request_completed)
	
	# Set initial progress bar ranges (Min is 0, Max is MAX_BASE_STAT)
	_setup_progress_bars()
	
	# 1. Configure the FileDialog
	file_dialog.filters = ["*.log;Nuzlocke Log Files"]
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.title = "Select Your Nuzlocke Randomizer Log File (.log)"
	
	# 2. Initial UI State
	file_path_label.text = "Click 'Load Log File' to load your randomized data."
	search_line_edit.editable = false # Disable search until log is loaded
	search_line_edit.placeholder_text = "Load a log..."
	results_list.clear()

	# 3. CRITICAL: Programmatic signal connection for search
	# This ensures the list updates whenever text changes.
	search_line_edit.text_changed.connect(_on_SearchLineEdit_text_changed)
	
	# 4. Connecting the selection signal (needed for the next step)
	results_list.item_selected.connect(_on_SearchResultsList_item_selected)
	
	# 5. NEW: Connect the focus signal for select_all functionality
	if is_instance_valid(search_line_edit):
		search_line_edit.connect("focus_entered", _on_search_line_edit_focus_entered)
	
	# NOTE: TextEdit does not have 'text_submitted'. We handle Enter press
	# using the _unhandled_input function instead.

# Called every frame to smooth the progress bar movement
func _process(_delta):
	# Update HP Bar
	if is_instance_valid(hpbar):
		hpbar.value = lerp(hpbar.value, float(target_stats.hp), BAR_LERP_SPEED)
	# Update Attack Bar
	if is_instance_valid(atkbar):
		atkbar.value = lerp(atkbar.value, float(target_stats.atk), BAR_LERP_SPEED)
	# Update Defense Bar
	if is_instance_valid(defbar):
		defbar.value = lerp(defbar.value, float(target_stats.def), BAR_LERP_SPEED)
	# Update Special Attack Bar
	if is_instance_valid(spabar):
		spabar.value = lerp(spabar.value, float(target_stats.spatk), BAR_LERP_SPEED)
	# Update Special Defense Bar
	if is_instance_valid(specialdefensebar):
		specialdefensebar.value = lerp(specialdefensebar.value, float(target_stats.spdef), BAR_LERP_SPEED)
	# Update Speed Bar
	if is_instance_valid(speedbar):
		speedbar.value = lerp(speedbar.value, float(target_stats.spd), BAR_LERP_SPEED)

# Sets up the max value for all ProgressBars
func _setup_progress_bars():
	var bars = [hpbar, atkbar, defbar, spabar, specialdefensebar, speedbar]
	for bar in bars:
		if is_instance_valid(bar):
			bar.min_value = 0
			bar.max_value = MAX_BASE_STAT
			bar.value = 0 # Start at zero

# --- Export Setter (Runs when data loading state changes) ---
func set_is_log_loaded(value):
	is_log_loaded = value
	if is_log_loaded:
		print("Log data successfully loaded into randomized_pokedex.")
		# Enable the search bar once the data is ready
		search_line_edit.editable = true
		search_line_edit.placeholder_text = "Pokémon name..."
		
	else:
		search_line_edit.editable = false
		search_line_edit.placeholder_text = "Load a log file..."
		results_list.clear() # Clear results if we lose data
		# Also clear the loaded Pokémon data
		loaded_pokemon = {}

# ==============================================================================
# 1. FILE LOADING & SIGNAL HANDLERS
# ==============================================================================

# Function connected to the 'pressed' signal of the LoadButton.
func _on_LoadButton_pressed():
	print("Load button pressed. Opening file dialog...")
	file_dialog.popup_centered()

# Function connected to the 'file_selected' signal of the FileDialog.
func _on_FileDialog_file_selected(path: String):
	print("File selected: %s" % path)
	file_path_label.text = "Reading file: " + path.get_file()
	
	read_log_file(path)

# Reads the content of the selected file path.
func read_log_file(path: String):
	var file = FileAccess.open(path, FileAccess.READ)
	
	if file:
		var content = file.get_as_text()
		file.close()
		parse_log_file(content)
		
		file_path_label.text = "Loaded successfully: " + path.get_file()
		# Use set_is_log_loaded to trigger UI updates
		self.is_log_loaded = true
		
		# --- CRITICAL: Call the search update NOW after data is confirmed loaded ---
		update_search_results("")
		# -----------------------------------------------------------------------------
		
	elif FileAccess.get_open_error() != OK:
		var error_msg = "Error opening file: " + error_string(FileAccess.get_open_error())
		print(error_msg)
		file_path_label.text = error_msg
		self.is_log_loaded = false

# ==============================================================================
# 2. DATA PARSING (The Core Logic)
# ==============================================================================

func parse_log_file(log_content: String):
	randomized_pokedex = {}
	print("--- Starting Log Parsing (Tabular Data Format) ---")
	
	var header_to_find = "( Pokemon Base Statistics / Types / Abilities {PKST} )"
	var data_header_line_start = "NUM|NAME"
	var end_separator = "=========================================================="

	# 1. Find the starting point of the stats section
	var start_index = log_content.find(header_to_find)
	
	if start_index == -1:
		printerr("ERROR: Could not find the section header '%s' in the log file." % header_to_find)
		return

	# 2. Trim the content to start just after the main header
	var stats_start = start_index + header_to_find.length()
	var content_after_start = log_content.substr(stats_start)
	
	# 3. Find the data table header line to mark the true start of data lines
	var data_header_index = content_after_start.find(data_header_line_start)
	if data_header_index == -1:
		printerr("ERROR: Could not find the data header line starting with '%s'." % data_header_line_start)
		return
		
	# Start parsing from the line *after* the data header
	var data_start_index = data_header_index + content_after_start.substr(data_header_index).find("\n") + 1
	var content_to_parse = content_after_start.substr(data_start_index)

	# 4. Find the end point (the next separator line)
	var end_index = content_to_parse.find(end_separator)
	
	if end_index != -1:
		# Trim the content to end just before the separator
		content_to_parse = content_to_parse.substr(0, end_index)
		
	var stats_section_content = content_to_parse
	
	if stats_section_content.strip_edges().is_empty():
		printerr("ERROR: Found the header, but the section content was empty or only contained whitespace.")
		return

	# 5. Iterate through the lines and extract data using split("|")
	for line in stats_section_content.split("\n"):
		var trimmed_line = line.strip_edges()
		if trimmed_line.is_empty():
			continue # Skip empty lines

		# Split the line by the pipe '|' character. This creates columns.
		var columns = trimmed_line.split("|")
		
		# The line format is: 
		# [0]   [1]           [2]              [3]  [4]  [5]  [6]  [7]  [8] [9]        [10]       [11]
		# 1|Bulbasaur|PSYCHIC/FIGHTING| 54| 67| 44| 27| 53| 73|Motor Drive|Battle Armor|HELD ITEM
		
		# Need at least 11 columns to safely extract all stats and one ability
		if columns.size() < 11:
			printerr("WARNING: Skipping line due to insufficient columns: %s" % trimmed_line)
			continue
			
		# Extract and clean data from columns
		var number_col = columns[0].strip_edges() # Ignored, but useful for validation
		var name = columns[1].strip_edges()
		var type_data = columns[2].strip_edges()
		
		# Stats are columns 3 through 8
		var hp_str = columns[3].strip_edges()
		var atk_str = columns[4].strip_edges()
		var def_str = columns[5].strip_edges()
		var spatk_str = columns[6].strip_edges()
		var spdef_str = columns[7].strip_edges()
		var spd_str = columns[8].strip_edges()

		var ability1 = columns[9].strip_edges()
		var ability2 = columns[10].strip_edges() # Can be "-"

		if name.is_empty() or not hp_str.is_valid_int() or not atk_str.is_valid_int():
			printerr("WARNING: Skipping invalid data line: %s" % trimmed_line)
			continue
		
		# --- Process Types ---
		var types = type_data.split("/")
		var type1 = types[0].strip_edges()
		var type2 = ""
		if types.size() > 1:
			type2 = types[1].strip_edges()
			
		# --- Process Abilities ---
		var abilities = []
		if ability1 != "-": abilities.append(ability1)
		if ability2 != "-": abilities.append(ability2)
		# Use global 'join' function for Godot 3.x compatibility
		var ability_str = " / ".join(abilities)

		# --- Conversion and Storage ---
		var name_key = name.to_upper() # Use uppercase for consistent dictionary key
		
		# Convert stat strings to integers
		var hp = int(hp_str)
		var atk = int(atk_str)
		var def = int(def_str)
		var spatk = int(spatk_str)
		var spdef = int(spdef_str)
		var spd = int(spd_str)
		
		# Calculate Base Stat Total (BST)
		var bst = hp + atk + def + spatk + spdef + spd
		
		randomized_pokedex[name_key] = {
			"name_display": name, # Store original casing for display
			"type1": type1,
			"type2": type2,
			"ability1": ability1,
			"ability2": ability2,
			"ability_str": ability_str, # Combined string for easy display
			"hp": hp,
			"atk": atk,
			"def": def,
			"spatk": spatk,
			"spdef": spdef,
			"spd": spd,
			"total": bst,
		}

	print("--- Log Parsing Complete. Loaded %d Pokémon ---" % randomized_pokedex.size())

	
# ==============================================================================
# 3. SEARCH & AUTCOMPLETE LOGIC
# ==============================================================================
func _input(event):
	if search_line_edit.has_focus():
		if event is InputEventKey and event.is_pressed():
			if event.key_label == KEY_SPACE or event.key_label == KEY_ENTER:
				get_viewport().set_input_as_handled()
				_select_first_result()
# Function connected to the 'text_changed' signal of SearchLineEdit.
func _on_SearchLineEdit_text_changed():
	if is_log_loaded and is_instance_valid(search_line_edit):
		var current_text = search_line_edit.text
		print("Updated search: ", current_text)
		update_search_results(current_text)

# Performs the search and updates the ItemList with results.
func update_search_results(search_term: String):
	# CRITICAL: Check if the list node is valid before trying to use it
	if not is_instance_valid(results_list):
		printerr("FATAL: Cannot update search results because the results_list node is invalid!")
		return
		
	var results = search_pokemon(search_term)
	print("Search results found: %d for term '%s'" % [results.size(), search_term])
	
	results_list.clear() # Clear old results
	
	if results.is_empty() and not search_term.is_empty():
		# Add a visual indicator if no results are found
		results_list.add_item("No Pokémon found matching '%s'" % search_term)
		
	# Add the results to the list, using the original display name
	for pname_key in results:
		# Retrieve the display name, defaulting to the key if not found (for safety)
		var display_name = randomized_pokedex.get(pname_key, {}).get("name_display", pname_key)
		results_list.add_item(display_name)

# Searches the loaded Pokedex for names matching the search term.
func search_pokemon(search_term: String) -> Array:
	var results = []
	var term_lower = search_term.to_lower().strip_edges()
	
	if randomized_pokedex.is_empty():
		return []
		
	# --- Explicitly handle empty search term (working for initial load) ---
	if term_lower.is_empty():
		# Return all keys, sorted.
		results = randomized_pokedex.keys().duplicate()
		results.sort()
		return results
		
	# Normal search logic for non-empty term
	for pname in randomized_pokedex.keys():
		# This will now only run for non-empty search terms
		if pname.to_lower().find(term_lower) != -1:
			results.append(pname)
			
	results.sort()
	return results
	
# Function connected to the 'item_selected' signal of the ResultsList (CRITICAL UPDATE)
func _on_SearchResultsList_item_selected(index: int):
	if index >= 0 and index < results_list.item_count:
		var selected_name = results_list.get_item_text(index)
		print("Selected Pokémon: " + selected_name)
		
		# 1. Update the search box and results (optional, but good UX)
		search_line_edit.text = selected_name
		update_search_results(selected_name)
		
		# 2. Populate the public 'loaded_pokemon' variable with details
		loaded_pokemon = get_pokemon_details(selected_name)
		
		# 3. Load the sprite image
		if loaded_pokemon.has("image_url") and not loaded_pokemon.image_url.is_empty():
			load_pokemon_sprite(loaded_pokemon.image_url)
			
		# 4. Update the UI with the new stats and info
		update_pokemon_ui(loaded_pokemon)
	pass

# --- NEW FUNCTION: The core logic to select the first item ---
func _select_first_result():
	# Ensure the list is valid and has at least one item
	if is_instance_valid(results_list) and results_list.item_count > 0:
		# Automatically select the first item (index 0) in the results list
		var index_to_select = 0
		
		# Manually set the selected item in the list for visual feedback
		results_list.select(index_to_select, true)
		
		# Now, manually trigger the selection logic using the existing signal handler
		_on_SearchResultsList_item_selected(index_to_select)
		
		# Return focus to the search bar 
		search_line_edit.grab_focus()

# --- Override input to handle Enter Key press in the TextEdit search bar ---
func _unhandled_input(event):
	# Check if the event is a key press, the key is pressed (not released), 
	# and the TextEdit node is currently focused.
	if is_instance_valid(search_line_edit) and search_line_edit.has_focus():
		if event is InputEventKey and event.pressed:
			# Check for Enter key (or Numpad Enter)
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				# Consume the input event so TextEdit doesn't process it as a newline
				get_viewport().set_input_as_handled()
				
				# Perform the selection logic
				_select_first_result()
				return # Stop further processing
	pass

# --- FIX APPLIED HERE: Defer the select_all call ---
func _on_search_line_edit_focus_entered() -> void:
	# CRITICAL FIX: Use call_deferred to wait for the engine's internal focus logic 
	# to finish before applying the selection. This prevents the engine from clearing it.
	search_line_edit.call_deferred("select_all")

# --- Updates all UI labels and sets progress bar targets ---
func update_pokemon_ui(data: Dictionary):
	if data.is_empty() or data.has("error"):
		# Clear UI if data is missing or invalid
		if is_instance_valid(typeLabel): typeLabel.text = "Type: N/A"
		if is_instance_valid(abilityLabel): abilityLabel.text = "Ability: N/A"
		
		# Set all labels and targets to 0
		var stat_labels = [hplabel, atklabel, deflabel, spalabel, specialdefenselabel, speedlabel]
		for label in stat_labels:
			if is_instance_valid(label):
				label.text = "0"
				
		target_stats = { "hp": 0, "atk": 0, "def": 0, "spatk": 0, "spdef": 0, "spd": 0 }
		return
		
	# 1. Update Type and Ability Labels
	if is_instance_valid(typeLabel):
		# Format is "Type1 / Type2" (already done in get_pokemon_details)
		typeLabel.text = "Type: " + data.types
	
	if is_instance_valid(abilityLabel):
		# Format is "Ability1 / Ability2"
		abilityLabel.text = "Ability: " + data.ability
	
	# 2. Update Stat Labels
	# Note: The data dictionary contains integer stats
	if is_instance_valid(hplabel): hplabel.text = str(data.hp)
	if is_instance_valid(atklabel): atklabel.text = str(data.atk)
	if is_instance_valid(deflabel): deflabel.text = str(data.def)
	if is_instance_valid(spalabel): spalabel.text = str(data.spatk)
	if is_instance_valid(specialdefenselabel): specialdefenselabel.text = str(data.spdef)
	if is_instance_valid(speedlabel): speedlabel.text = str(data.spd)
	
	# 3. Update Lerp Targets for Progress Bars
	target_stats = {
		"hp": data.hp,
		"atk": data.atk,
		"def": data.def,
		"spatk": data.spatk,
		"spdef": data.spdef,
		"spd": data.spd,
	}

# Retrieves the full data for a specific Pokémon (Unchanged, returns all parsed stats).
func get_pokemon_details(pname: String) -> Dictionary:
	var pokemon_name = pname.to_upper()
	
	if not randomized_pokedex.has(pokemon_name):
		return {"error": "Pokémon not found."}
		
	var data = randomized_pokedex[pokemon_name]
	
	# Image URL construction
	# NOTE: We use the original 'name' (Bulbasaur) for the image lookup
	var image_name = pname.to_lower().replace(" ", "-").replace(".", "").replace("'", "")
	# Fix for Nidoran male/female - replace special characters
	image_name = image_name.replace("♂", "-m").replace("♀", "-f")
	var image_url = POKEMON_SPRITE_BASE_URL + image_name + ".png"

	# Format display strings
	var types_str = data.type1
	if not data.type2.is_empty():
		types_str += " / " + data.type2
		
	var stats_str = "HP: %d, Atk: %d, Def: %d, SpAtk: %d, SpDef: %d, Spd: %d (BST: %d)" % [
		data.hp, data.atk, data.def, data.spatk, data.spdef, data.spd, data.total
	]
	
	# Return the dictionary containing all processed data fields, ready for UI binding
	# Importantly, it returns the raw integer stats needed for the progress bars.
	return {
		"name": data.name_display,
		"types": types_str,
		"base_stats_summary": stats_str,
		"image_url": image_url,
		"ability": data.ability_str,
		"hp": data.hp,
		"atk": data.atk,
		"def": data.def,
		"spatk": data.spatk,
		"spdef": data.spdef,
		"spd": data.spd,
		"total": data.total,
	}

# ==============================================================================
# 5. IMAGE LOADING LOGIC
# ==============================================================================

# Initiates an asynchronous request to download the image.
func load_pokemon_sprite(url: String):
	if not is_instance_valid(image_loader):
		printerr("Error: Cannot load image. HTTPRequest node 'HTTPRequest' is invalid.")
		return
	
	# Clear previous request and set timeout
	image_loader.cancel_request()
	image_loader.set_timeout(10) # 10 seconds timeout
	
	print("Requesting image from URL: %s" % url)
	
	var error = image_loader.request(url)
	if error != OK:
		printerr("Error starting HTTP request: %s" % error_string(error))
		if is_instance_valid(sprite):
			sprite.texture = null # Clear on request failure

# Callback function called when the HTTP request finishes.
func _on_http_request_completed(result, response_code, _headers, body):
	if not is_instance_valid(sprite):
		printerr("Sprite2D node is invalid. Cannot set texture.")
		return
		
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		printerr("Image request failed. Result: %s, Code: %d. Note: Sprite URL might be wrong for specific Pokémon (e.g., forms/gender)." % [result, response_code])
		sprite.texture = null # Clear the sprite on network failure
		return

	# Attempt to load the image from the binary body data
	var image = Image.new()
	var error = image.load_jpg_from_buffer(body)
	
	if error != OK:
		# If it failed as JPG, try loading as PNG (fallback)
		error = image.load_png_from_buffer(body)
	
	if error == OK:
		var texture = ImageTexture.create_from_image(image)
		sprite.texture = texture
		print("Successfully loaded and displayed sprite.")
	else:
		printerr("Error loading image from buffer: %s" % error_string(error))
		sprite.texture = null # Clear on image decoding failure

func _on_pokemon_button_pressed() -> void:
	$LearnsetScreen.visible = false

func _on_learnset_button_pressed() -> void:
	$LearnsetScreen.visible = true
