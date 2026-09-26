extends Node2D

@onready var world: TileMapLayer = $World

enum TileState {
	DIRT = 0,
	CANAL = 1,
	GRASS = 2,
	WATER = 3
}

var grid_data: Dictionary = {}
var main_source_id: int = 0

var is_flowing: bool = false
var flow_queue: Array[Vector2i] = []

func _ready() -> void:
	var used_cells = world.get_used_cells()
	for cell in used_cells:
		var atlas_coord = world.get_cell_atlas_coords(cell)
		grid_data[cell] = atlas_coord.x
		main_source_id = world.get_cell_source_id(cell)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		var mouse_pos = get_global_mouse_position()
		var clicked_cell = world.local_to_map(mouse_pos)
		
		if grid_data.has(clicked_cell):
			perform_digging(clicked_cell)

func perform_digging(cell_pos: Vector2i) -> void:
	var current_state = grid_data[cell_pos]
	
	if current_state == TileState.DIRT or current_state == TileState.GRASS:
		change_tile_state(cell_pos, TileState.CANAL)
		check_and_trigger_flow(cell_pos)

func change_tile_state(cell_pos: Vector2i, new_state: int) -> void:
	grid_data[cell_pos] = new_state
	world.set_cell(cell_pos, main_source_id, Vector2i(new_state, 0))

func check_and_trigger_flow(start_cell: Vector2i) -> void:
	if has_neighbor_of_type(start_cell, TileState.WATER):
		if not flow_queue.has(start_cell):
			flow_queue.append(start_cell)
		
		if not is_flowing:
			process_flow_queue()
	else:
		for cell in grid_data.keys():
			if grid_data[cell] == TileState.CANAL and has_neighbor_of_type(cell, TileState.WATER):
				if not flow_queue.has(cell):
					flow_queue.append(cell)
		
		if flow_queue.size() > 0 and not is_flowing:
			process_flow_queue()

func process_flow_queue() -> void:
	is_flowing = true
	
	while flow_queue.size() > 0:
		var current_batch = flow_queue.duplicate()
		flow_queue.clear()
		
		var changes_made = false
		
		for cell in current_batch:
			if grid_data[cell] == TileState.CANAL:
				change_tile_state(cell, TileState.WATER)
				changes_made = true
				
				var neighbors = world.get_surrounding_cells(cell)
				for n in neighbors:
					if grid_data.has(n):
						if grid_data[n] == TileState.CANAL and not flow_queue.has(n):
							flow_queue.append(n)
						elif grid_data[n] == TileState.DIRT:
							change_tile_state(n, TileState.GRASS)
		
		if changes_made:
			await get_tree().create_timer(0.5).timeout
			
	is_flowing = false

func has_neighbor_of_type(cell_pos: Vector2i, target_type: int) -> bool:
	var neighbors = world.get_surrounding_cells(cell_pos)
	for n in neighbors:
		if grid_data.has(n) and grid_data[n] == target_type:
			return true
	return false
