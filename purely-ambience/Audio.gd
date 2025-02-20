@tool
@icon("res://addons/purely-ambience/PurelyIcon.svg")
extends Node3D

## ====================== EXPORTED VARIABLES ======================
@export_category(" WHO HEARS THIS ")
@export var player_node: CharacterBody3D

@export_category(" AUDIO STREAM ")
@export var audio_stream: AudioStream

@export_category(" VOLUME SETTINGS ")
@export_range(-80.0, 80.0, 0.1) var max_volume_db: float = 0.0
@export_range(-80.0, 80.0, 0.1) var min_volume_db: float = 0.0

@export_category(" DISTANCE SETTINGS ")
@export var max_distance_fallback: float = 60.0
@export var trigger_distance: float = 0.0
@export var fade_range: float = 15.0

@export_category(" SMOOTHING ")
@export var volume_lerp_speed: float = 5.0

@export_category(" LOGIC TOGGLES ")
@export var priority: bool = false
@export var mute_outersources: bool = false
@export var show_debug: bool = false

@export_category(" INSIDE AMBIENCE ")
@export var inside_ambience: bool = false
# New lerp speed when transitioning into an inside ambience:
@export var inside_volume_lerp_speed: float = 10.0
# Dimensions for the box trigger (full size, not half-extents)
@export var trigger_box_size: Vector3 = Vector3.ONE

## ====================== CONSTANTS & INTERNALS ======================
const VOLUME_OFF_DB: float = -80.0
# This name is used locally as a child node – each duplicate gets its own debug trigger.
const DEBUG_TRIGGER_NODE: String = "DebugTrigger"

var audio_player_node: AudioStreamPlayer

## ====================== READY ======================
func _ready() -> void:
	add_to_group("AudioAmbienceNodes")
	
	if not Engine.is_editor_hint():
		audio_player_node = AudioStreamPlayer.new()
		audio_player_node.name = "StreamAmbient"
		add_child(audio_player_node)
		audio_player_node.stream = audio_stream
		audio_player_node.volume_db = VOLUME_OFF_DB
		audio_player_node.play()
	
	if Engine.is_editor_hint():
		_update_debug_trigger()

## ====================== PROCESS (EDITOR) ======================
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_update_debug_trigger()
		
## ====================== PHYSICS PROCESS (GAME) ======================
func _physics_process(delta: float) -> void:
	if not Engine.is_editor_hint():
		_apply_ambience_logic(delta)

## ====================== AMBIENCE LOGIC ======================
func _apply_ambience_logic(delta: float) -> void:
	# Null checks.
	if player_node == null or audio_player_node == null:
		return

	var target_volume_db: float = 0.0

	# Use box-based volume calculation for inside ambience,
	# otherwise fall back to sphere-based.
	if inside_ambience == true:
		target_volume_db = _calculate_volume_box()
	else:
		var distance_to_player = player_node.global_position.distance_to(global_position)
		target_volume_db = _calculate_volume_sphere(distance_to_player)
	
	# For non-inside ambience nodes, if any inside ambience node is active, mute this node.
	if inside_ambience == false:
		for node in get_tree().get_nodes_in_group("AudioAmbienceNodes"):
			if node == self:
				continue
			if node.inside_ambience == true:
				# Check using the box trigger for the inside ambience node.
				var local_player = node.global_transform.affine_inverse() * player_node.global_position
				var half_size = node.trigger_box_size * 0.5
				if abs(local_player.x) <= half_size.x and abs(local_player.y) <= half_size.y and abs(local_player.z) <= half_size.z:
					target_volume_db = VOLUME_OFF_DB
					break

	# Existing priority logic.
	if priority == false:
		for node in get_tree().get_nodes_in_group("AudioAmbienceNodes"):
			if node == self:
				continue
			if node is Node3D and node.priority == true:
				if node.trigger_distance > 0.0:
					var dist_to_priority = player_node.global_position.distance_to(node.global_position)
					if dist_to_priority <= node.trigger_distance:
						if mute_outersources == true:
							target_volume_db = VOLUME_OFF_DB
						else:
							target_volume_db = max(VOLUME_OFF_DB, target_volume_db - 10.0)
						break

	var lerp_speed: float = volume_lerp_speed
	if inside_ambience == true:
		lerp_speed = inside_volume_lerp_speed

	audio_player_node.volume_db = lerp(audio_player_node.volume_db, target_volume_db, lerp_speed * delta)

## ====================== VOLUME CALCULATION (SPHERE) ======================
func _calculate_volume_sphere(distance: float) -> float:
	if trigger_distance > 0.0:
		if distance <= trigger_distance:
			return max_volume_db
		elif distance <= trigger_distance + fade_range:
			var fade_factor = 1.0 - ((distance - trigger_distance) / fade_range)
			return lerp(VOLUME_OFF_DB, max_volume_db, fade_factor)
		else:
			return VOLUME_OFF_DB
	else:
		var global_ratio = clamp(distance / max_distance_fallback, 0.0, 1.0)
		return lerp(min_volume_db, max_volume_db, global_ratio)

## ====================== VOLUME CALCULATION (BOX for Inside Ambience) ======================
func _calculate_volume_box() -> float:
	# Convert the player's global position to the local space of this node.
	var local_player = global_transform.affine_inverse() * player_node.global_position
	var half_size = trigger_box_size * 0.5
	if abs(local_player.x) <= half_size.x and abs(local_player.y) <= half_size.y and abs(local_player.z) <= half_size.z:
		return max_volume_db
	else:
		# Calculate the shortest distance from the player to the box's surface.
		var dx = max(0, abs(local_player.x) - half_size.x)
		var dy = max(0, abs(local_player.y) - half_size.y)
		var dz = max(0, abs(local_player.z) - half_size.z)
		var distance = sqrt(dx * dx + dy * dy + dz * dz)
		if distance <= fade_range:
			var fade_factor = 1.0 - (distance / fade_range)
			return lerp(VOLUME_OFF_DB, max_volume_db, fade_factor)
		else:
			return VOLUME_OFF_DB

## ====================== DEBUG TRIGGER (EDITOR ONLY) ======================
func _update_debug_trigger() -> void:
	# If no valid trigger is defined, remove the debug node.
	if (inside_ambience == false and trigger_distance <= 0.0) or (inside_ambience == true and trigger_box_size == Vector3.ZERO):
		var old_trigger = self.get_node_or_null(DEBUG_TRIGGER_NODE)
		if old_trigger:
			old_trigger.queue_free()
		return
	
	var debug_trigger = self.get_node_or_null(DEBUG_TRIGGER_NODE) as MeshInstance3D
	if debug_trigger == null:
		debug_trigger = MeshInstance3D.new()
		debug_trigger.name = DEBUG_TRIGGER_NODE
		add_child(debug_trigger)
	
	# Choose the appropriate mesh based on inside_ambience.
	if inside_ambience == true:
		# Always create a new BoxMesh instance to avoid sharing the resource.
		var box_mesh = BoxMesh.new()
		box_mesh.size = trigger_box_size
		box_mesh.resource_local_to_scene = true
		debug_trigger.mesh = box_mesh
	else:
		# Always create a new SphereMesh instance for normal ambience.
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = 1.0
		sphere_mesh.resource_local_to_scene = true
		debug_trigger.mesh = sphere_mesh
	
	# Re-add material settings for both box and sphere.
	if not (debug_trigger.material_override is StandardMaterial3D):
		var mat_trigger = StandardMaterial3D.new()
		mat_trigger.flags_unshaded = true
		mat_trigger.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if priority == true:
			mat_trigger.albedo_color = Color(0, 1, 0, 0.3)
		else:
			mat_trigger.albedo_color = Color(1, 0, 0, 0.3)
		debug_trigger.material_override = mat_trigger
	else:
		var mat_trigger = debug_trigger.material_override as StandardMaterial3D
		debug_trigger.material_override.resource_local_to_scene = true
		if priority == true:
			mat_trigger.albedo_color = Color(0, 1, 0, 0.3)
		else:
			mat_trigger.albedo_color = Color(1, 0, 0, 0.3)
	
	# Toggle visibility based on debug settings.
	if inside_ambience == true:
		debug_trigger.visible = show_debug and trigger_box_size != Vector3.ZERO
	else:
		debug_trigger.visible = show_debug and trigger_distance > 0.0
	
	# Update transform to ignore parent's scale (same for sphere and box).
	var parent_tf_no_scale = global_transform
	var parent_scale = parent_tf_no_scale.basis.get_scale()
	if parent_scale.x != 0 and parent_scale.y != 0 and parent_scale.z != 0:
		parent_tf_no_scale.basis = parent_tf_no_scale.basis.scaled(Vector3(1.0 / parent_scale.x, 1.0 / parent_scale.y, 1.0 / parent_scale.z))
	debug_trigger.global_transform = parent_tf_no_scale
	
	# For sphere triggers, apply additional scaling; for box triggers, the mesh size is already defined.
	if inside_ambience == false:
		debug_trigger.scale = Vector3.ONE * trigger_distance
	else:
		debug_trigger.scale = Vector3.ONE
