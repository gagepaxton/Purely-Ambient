@tool
extends EditorPlugin

const PURELY_ICON = preload("res://addons/purely-ambience/PurelyIcon.svg")
const AUDIO_SOURCE = preload("res://addons/purely-ambience/audio_source.tscn")
const Audio = preload("res://addons/purely-ambience/Audio.gd")

func _enter_tree() -> void:
	# Register the custom type by passing the script (not the PackedScene).
	add_custom_type("Ambient-Source", "Node3D", Audio, PURELY_ICON)

func _exit_tree() -> void:
	remove_custom_type("AudioAmbience")
