class_name KillableObject extends Node

# const implements = [preload("res://example/can_take_damage.gd")]
const implements = ["IDamagable"]

signal damage


func deal_damage(dmg: int) -> void:
	pass

func _ready() -> void:
	# print(Interfaces.implements(self, IDamagable))
	pass


# Vallidation occurs at project startup.
