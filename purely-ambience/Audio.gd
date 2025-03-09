@tool
@icon("res://addons/purely-ambience/PurelyIcon.svg")
class_name PurelyAmbient3D extends Node3D

## ====================== EXPORTED VARIABLES ======================
@export_category(" WHO HEARS THIS ")
##(Optional) if is empty, this use current camera/listener as the "listener node"
@export var listener_node: Node3D

@export_category(" AUDIO STREAM ")
##Audio required for play by PurelyAmbient3D
@export var audio_stream: AudioStream:
	set(e):
		audio_stream = e
		var node : AudioStreamPlayer = get_node_or_null("StreamAmbient")
		if node:
			if null != audio_stream:
				node.stream = audio_stream
				node.play()
				set_physics_process(true)
			else:
				node.stop()
				set_physics_process(false)

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


## ====================== TREE =======================
var tick : int = 0
var tick_wait : int = 15
var dynamic_listener : bool = false
const LISTENER_GROUP_KEY : StringName = &"AudioListener3D"

func _enter_tree() -> void:
	dynamic_listener = null == listener_node
	if dynamic_listener:
		tick_wait = max(0, roundi(Engine.physics_ticks_per_second / 15))
		tick = tick_wait
		if !get_tree().node_added.is_connected(PurelyAmbient3D._on_node_tree_added):
			get_tree().node_added.connect(PurelyAmbient3D._on_node_tree_added)
			PurelyAmbient3D._on_node_tree_added(get_tree().root)

static func _on_node_tree_added(n : Node) -> void:
	if !n.is_node_ready():
		await n.ready
	if n is AudioListener3D:
		if !n.is_in_group(LISTENER_GROUP_KEY):
			n.add_to_group(LISTENER_GROUP_KEY)
	for x : Node in n.get_children():
		_on_node_tree_added(x)

## ====================== READY ======================
func _ready() -> void:
	add_to_group(&"AudioAmbienceNodes")

	set_process(false)
	set_physics_process(false)

	if not Engine.is_editor_hint():
		audio_player_node = AudioStreamPlayer.new()
		audio_player_node.name = &"StreamAmbient"
		add_child(audio_player_node)
		audio_player_node.volume_db = VOLUME_OFF_DB
		audio_player_node.stream = audio_stream
		if audio_stream:
			audio_player_node.play()
		else:
			push_warning("Audio stream not defined ", get_path())
		set_physics_process(audio_stream != null)

	if Engine.is_editor_hint():
		_update_debug_trigger()
		set_process(true)

## ====================== PROCESS (EDITOR) ======================
func _process(delta: float) -> void:
	#if Engine.is_editor_hint():
		#_update_debug_trigger()
	_update_debug_trigger()

## ====================== PHYSICS PROCESS (GAME) ======================
func _physics_process(delta: float) -> void:
	#if not Engine.is_editor_hint():
		#_apply_ambience_logic(delta)
	_apply_ambience_logic(delta)

## ====================== AMBIENCE LOGIC ======================
func _apply_ambience_logic(delta: float) -> void:
	# Null checks.
	tick += 1
	if tick > tick_wait:
		tick = 0
		#tick_wait = max(0, roundi(Engine.physics_ticks_per_second / 15)) ## Uncomment for rare games ticks change in runtime
		if dynamic_listener:
			var active : Node3D = null
			var listeners : Array[Node] = get_tree().get_nodes_in_group(LISTENER_GROUP_KEY)
			for x in listeners:
				x.clear_current()
			for ilistener0 : int in range(0, listeners.size(), 1):
				var listener : Node = listeners[ilistener0]
				if listener.is_current():
					active = listener
					#region unique_listener
					#That bug was apparently fixed in later versions, so I'll leave the code anyway.
					#Secure unique listener is enabled, see AudioListener3D.is_current() docs.
					#var dirty : bool = false
					#for ilistener1 : int in range(ilistener0 + 1, listeners.size(), 1):
						#listener = listeners[ilistener1]
						#if listener.is_current():
							#listener.clear_current()
							#dirty = true
					#if dirty:
						#listener.make_current()
					#endregion
					break
			if null == active:
				active = get_viewport().get_camera_3d()
			listener_node = active
		#else:
			#if listener_node is Camera3D:
				##Maybe User-default camera/listeners preference handler
				#dynamic_listener = true

	if listener_node == null: return



	var target_volume_db: float = 0.0

	# Use box-based volume calculation for inside ambience,
	# otherwise fall back to sphere-based.
	if inside_ambience == true:
		target_volume_db = _calculate_volume_box()
	else:
		var distance_to_player : float = listener_node.global_position.distance_to(global_position)
		target_volume_db = _calculate_volume_sphere(distance_to_player)

	# For non-inside ambience nodes, if any inside ambience node is active, mute this node.
	if inside_ambience == false:
		for node in get_tree().get_nodes_in_group(&"AudioAmbienceNodes"):
			if node == self:
				continue
			if node.inside_ambience == true:
				# Check using the box trigger for the inside ambience node.
				var local_player : Vector3 = node.global_transform.affine_inverse() * listener_node.global_position
				var half_size : Vector3 = node.trigger_box_size * 0.5
				if absf(local_player.x) <= half_size.x and absf(local_player.y) <= half_size.y and absf(local_player.z) <= half_size.z:
					target_volume_db = VOLUME_OFF_DB
					break

	# Existing priority logic.
	if priority == false:
		for node in get_tree().get_nodes_in_group(&"AudioAmbienceNodes"):
			if node == self:
				continue
			if node is PurelyAmbient3D and node.priority == true:
				if node.trigger_distance > 0.0:
					var dist_to_priority : float = listener_node.global_position.distance_to(node.global_position)
					if dist_to_priority <= node.trigger_distance:
						if mute_outersources == true:
							target_volume_db = VOLUME_OFF_DB
						else:
							target_volume_db = maxf(VOLUME_OFF_DB, target_volume_db - 10.0)
						break

	var lerp_speed: float = volume_lerp_speed
	if inside_ambience == true:
		lerp_speed = inside_volume_lerp_speed

	audio_player_node.volume_db = lerpf(audio_player_node.volume_db, target_volume_db, lerp_speed * delta)

## ====================== VOLUME CALCULATION (SPHERE) ======================
func _calculate_volume_sphere(distance: float) -> float:
	if trigger_distance > 0.0:
		if distance <= trigger_distance:
			return max_volume_db
		elif distance <= trigger_distance + fade_range:
			var fade_factor = 1.0 - ((distance - trigger_distance) / fade_range)
			return lerpf(VOLUME_OFF_DB, max_volume_db, fade_factor)
		else:
			return VOLUME_OFF_DB
	else:
		var global_ratio : float = clampf(distance / max_distance_fallback, 0.0, 1.0)
		return lerpf(min_volume_db, max_volume_db, global_ratio)

## ====================== VOLUME CALCULATION (BOX for Inside Ambience) ======================
func _calculate_volume_box() -> float:
	# Convert the player's global position to the local space of this node.
	var local_player : Vector3 = global_transform.affine_inverse() * listener_node.global_position
	var half_size = trigger_box_size * 0.5
	if absf(local_player.x) <= half_size.x and absf(local_player.y) <= half_size.y and absf(local_player.z) <= half_size.z:
		return max_volume_db
	else:
		# Calculate the shortest distance from the player to the box's surface.
		var dx : float = maxf(0.0, absf(local_player.x) - half_size.x)
		var dy : float = maxf(0.0, absf(local_player.y) - half_size.y)
		var dz : float = maxf(0.0, absf(local_player.z) - half_size.z)
		var distance = sqrt(dx * dx + dy * dy + dz * dz)
		if distance <= fade_range:
			var fade_factor = 1.0 - (distance / fade_range)
			return lerpf(VOLUME_OFF_DB, max_volume_db, fade_factor)
		else:
			return VOLUME_OFF_DB

## ====================== DEBUG TRIGGER (EDITOR ONLY) ======================
func _update_debug_trigger() -> void:
	# If no valid trigger is defined, remove the debug node.
	if (inside_ambience == false and trigger_distance <= 0.0) or (inside_ambience == true and trigger_box_size == Vector3.ZERO):
		var old_trigger : Node = self.get_node_or_null(DEBUG_TRIGGER_NODE)
		if old_trigger:
			old_trigger.queue_free()
		return

	var debug_trigger : MeshInstance3D = self.get_node_or_null(DEBUG_TRIGGER_NODE) as MeshInstance3D
	if debug_trigger == null:
		debug_trigger = MeshInstance3D.new()
		debug_trigger.name = DEBUG_TRIGGER_NODE
		add_child(debug_trigger)

	# Choose the appropriate mesh based on inside_ambience.
	if inside_ambience == true:
		# Always create a new BoxMesh instance to avoid sharing the resource.
		var box_mesh : BoxMesh = BoxMesh.new()
		box_mesh.size = trigger_box_size
		box_mesh.resource_local_to_scene = true
		debug_trigger.mesh = box_mesh
	else:
		# Always create a new SphereMesh instance for normal ambience.
		var sphere_mesh : SphereMesh = SphereMesh.new()
		sphere_mesh.radius = 1.0
		sphere_mesh.resource_local_to_scene = true
		debug_trigger.mesh = sphere_mesh

	# Re-add material settings for both box and sphere.
	if not (debug_trigger.material_override is StandardMaterial3D):
		var mat_trigger : StandardMaterial3D = StandardMaterial3D.new()
		mat_trigger.flags_unshaded = true
		mat_trigger.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if priority == true:
			mat_trigger.albedo_color = Color(0, 1, 0, 0.3)
		else:
			mat_trigger.albedo_color = Color(1, 0, 0, 0.3)
		debug_trigger.material_override = mat_trigger
	else:
		var mat_trigger : StandardMaterial3D = debug_trigger.material_override as StandardMaterial3D
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
	var parent_tf_no_scale : Transform3D = global_transform
	var parent_scale : Vector3 = parent_tf_no_scale.basis.get_scale()
	if parent_scale.x != 0 and parent_scale.y != 0 and parent_scale.z != 0:
		parent_tf_no_scale.basis = parent_tf_no_scale.basis.scaled(Vector3(1.0 / parent_scale.x, 1.0 / parent_scale.y, 1.0 / parent_scale.z))
	debug_trigger.global_transform = parent_tf_no_scale

	# For sphere triggers, apply additional scaling; for box triggers, the mesh size is already defined.
	if inside_ambience == false:
		debug_trigger.scale = Vector3.ONE * trigger_distance
	else:
		debug_trigger.scale = Vector3.ONE
