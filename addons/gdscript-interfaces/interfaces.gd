extends Node

##
## A library providing a runtime interface system for GDScript
##
## @desc:
##     This library provides interfaces for GDScript that can either be validated
##     at runtime when they are used or at application start (also runtime).
##     The code is MIT-licensed.
##
## @tutorial: https://github.com/nsrosenqvist/gdscript-interfaces/tree/main/addons/gdscript-interfaces#readme
##
const LOCAL_PATH := "res://"
const IGNORE_DIRS: Array[String] = [".godot", ".git", "build"]

@export var allow_string_classes: bool = true
@export var strict_validation: bool = true
@export var strict_interface_name: bool = true

var _global_class_list := ProjectSettings.get_global_class_list()
var _global_class_names := _column(_global_class_list, "class").map(func(el): return str(el))
var _interfaces := {}
var _identifiers := {}
var _implements := {}

## Validate that an entity implements an interface
##
## implementation [Object]: Any GDscript or a node with script attached
## interfaces [GDScript|Array]: The interface(s) to validate against
## validate [bool]: Whether validation should run or if only the
##                  implements constant should be checked
## assert_on_fail [bool]: Instead of returning false, cause an assertion.
##                        This is an option that gets set automatically
##                        enabling runtime validation.
##
## Returns a [bool] indicating the result of the validation
func implements(implementation, interfaces, validate=strict_validation, assert_on_fail=true) -> bool:
	if not (interfaces is Array):
		interfaces = [interfaces]

	var script: GDScript = _get_script(implementation)
	var implemented: Array = _get_implements(script)

	if implemented.size() == 0:
		return false

	for i in interfaces:
		if not implemented.has(i):
			return false

		var implementation_id: String = _get_identifier(script)
		var interface_id: String = _get_identifier(i)

		if validate:
			if not _validate(script, i, assert_on_fail):
				return false
		else:
			if i not in implemented:
				if assert_on_fail:
					#var lookup: String = str(script) + "==" + str(i)
					assert(false, "'%s' doesnt implement '%s'. As it not has a script." % [implementation_id, interface_id])
				else:
					return false
	return true

## Filter an array of objects and keep the ones implementing the interfaces
##
## objects [Array]: List of objects to filter
## interface [GDScript|Array]: The interface(s) to validate against
## validate [bool]
##
## Returns an [Array] containing the objects that implements the interface(s)
func implementations(objects: Array, interfaces, validate=false) -> Array:
	var result = []

	for object in objects:
		if implements(object, interfaces, validate):
			result.append(object)

	return result

func _init():
	if OS.has_feature("editor"):
		#print('Global Class List:')
		#print(_global_class_list)
		# Pre-validate all interfaces on game start
		_validate_all_implementations()

func _validate_all_implementations() -> void:
	# Get all script files
	var files := _get_all_files(LOCAL_PATH)
	var scripts = []

	for f in files:
		if f.ends_with(".gd"):
			scripts.append(f)

	# Validate all scripts that has the constant "implements"
	for s in scripts:
		var script = load(s)
		var identifier = _get_identifier(script)
		var implemented = _get_implements(script)

		if implemented.size() > 0:
			implements(script, implemented, strict_validation, true)

func _get_all_files(path: String) -> PackedStringArray:
	var cur_dir := DirAccess.open(path)
	if not cur_dir:
		printerr("An error occurred when trying to access '%s'." % [path])
		return []

	cur_dir.include_navigational=false	# ignore '.' and '..'
	var files := cur_dir.get_files()
	for i in range(files.size()):
		files[i] = path.path_join(files[i])
	var dirs := cur_dir.get_directories()
	for i in range(dirs.size()):
		dirs[i] = path.path_join(dirs[i])

	var i := 0
	while i < dirs.size():
		var d = dirs[i]
		cur_dir.change_dir(d)

		var path_tokens = d.split('/')
		var dir_name = path_tokens[path_tokens.size()-1]
		if dir_name not in IGNORE_DIRS:
			var nfiles := cur_dir.get_files()
			for j in range(nfiles.size()):
				nfiles[j] = cur_dir.get_current_dir().path_join(nfiles[j])
			files.append_array(nfiles)

			var ndirs := cur_dir.get_directories()
			for j in range(ndirs.size()):
				ndirs[j] = cur_dir.get_current_dir().path_join(ndirs[j])
			dirs.append_array(ndirs)
		i+=1

	return files

func _column(rows: Array, key: String) -> Array:
	var result := []

	for row in rows:
		result.append(row.get(key))

	return result

func _get_script(implementation) -> GDScript:
	if not implementation is GDScript:
		return implementation.get_script()

	return implementation

# Validate implementation's _implements_ const usage.
func _get_implements(implementation: Resource) -> Array:
	var script: GDScript = _get_script(implementation)
	var lookup: String = str(script)

	if _implements.has(lookup):
		return _implements[lookup]

	# Get implements constant from script
	var consts: Dictionary = script.get_script_constant_map()

	if consts.has("implements"):
		var interfaces: Array[GDScript] = []
		for interface in consts["implements"]:
			if interface is String:
				if strict_interface_name:
					assert(interface.begins_with("I"), "Interface '%s' not starts with 'I' (Path: '%s')." % [interface, script.resource_path])
				assert(interface in _global_class_names, "Interface '%s' not found in global class list. Check if declaration is correct in '%s'." % [interface, script.resource_path])
				assert(allow_string_classes, "Cannot use string type in implements as 'allow_string_classes' is false. ('%s' in %s)" % [interface, lookup])
				# WARN: Collateral effect on release mode, the asserts will be stripped out
				# and the execution will follow
				interfaces.append(_get_interface_script(interface))
			elif interface is GDScript:
				interfaces.append(interface)
		_implements[lookup] = interfaces
	else:
		_implements[lookup] = []

	return _implements[lookup]

func _get_interface_script(interface_name):
	var script = GDScript.new()
	# Loads the script using via class_name
	script.set_source_code("func eval(): return " + interface_name)
	script.reload()
	var ref = RefCounted.new() # ?
	ref.set_script(script)
	return ref.eval()

func _get_identifier(implementation, strict=false) -> String:
	var script: GDScript = _get_script(implementation)
	var lookup: String = str(script)

	if _identifiers.has(lookup):
		return _identifiers[lookup]

	# Extract class_name from script
	if script.has_source_code():
		var regex: RegEx = RegEx.new()
		regex.compile("class_name\\W+(\\w+)");
		var result = regex.search(script.source_code);

		if result:
			_identifiers[lookup] = result.get_string().substr(11)
		else:
			_identifiers[lookup] = "" if strict else script.resource_path

		return _identifiers[lookup]

	return "Unknown"

func _validate_implementation(script: GDScript, interface: GDScript, assert_on_fail=false) -> bool:
	var implementation_id = _get_identifier(script)
	var interface_id = _get_identifier(interface)

	if not interface.has_source_code():
		return true
	elif not script.has_source_code():
		if assert_on_fail:
			assert(false, "'%s' doesnt implement '%s'. As it not has a script." % [implementation_id, interface_id])
		else:
			return false

	# Check signals
	var signals = _column(script.get_script_signal_list(), "name")
	for s in _column(interface.get_script_signal_list(), "name"):
		if not (s in signals):
			if assert_on_fail:
				assert(false, "'%s' doesnt implement the signal '%s' of the interface '%s'." % [implementation_id, s, interface_id])
			else:
				return false

	# Check methods
	var methods = _column(script.get_script_method_list(), "name")
	for m in _column(interface.get_script_method_list(), "name"):
		if not (m in methods):
			if assert_on_fail:
				assert(false, "'%s' doesnt implement the method '%s' of the interface '%s'." % [implementation_id, m, interface_id])
			else:
				return false

	return true

func _validate(implementation, interface: GDScript, assert_on_fail=false) -> bool:
	var script: GDScript = _get_script(implementation)
	var lookup: String = str(script) + "==" + str(interface)

	if _interfaces.has(lookup):
		return _interfaces[lookup]

	# Save to look up dictionary
	_interfaces[lookup] = _validate_implementation(script, interface, assert_on_fail)

	return _interfaces[lookup]


# * Only works when running the project from the editor.
# * Runs in the same thread as the game.
# TODO: Refactor the code to run in a isolated thread.
# TODO: Research if is possible to run it in the editor, without needing to run the game (F5).
# https://gamedev.stackexchange.com/questions/208348/is-there-a-way-to-instantiate-a-custom-class-decided-at-runtime-in-gdscript
