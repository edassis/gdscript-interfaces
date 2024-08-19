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
const IGNORE_DIRS: Array[String] = [".godot", ".git", "addons", "build"]

@export var allow_string_classes: bool = true
@export var strict_validation: bool = true
@export var strict_interface_name: bool = true

var _global_class_list := ProjectSettings.get_global_class_list()
var _global_class_names := _column(_global_class_list, "class").map(func(el): return str(el))
var _interfaces := {}
var _identifiers := {}
var _implements := {}

var _global_classes := _paths2dicts(_global_class_list)
var _interfaces_objs := {}

func _paths2dicts(ar: Array[Dictionary]) -> Dictionary:
	var ans := {}
	for global_class in _global_class_list:
		var path: String = global_class["path"]
		ans[path] = global_class
	return ans

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
func implements(implementation, interfaces, validate, assert_on_fail=true) -> bool:
	if interfaces is not Array:
		interfaces = [interfaces]

	var script: GDScript = _get_script(implementation)
	var implements: Array = _get_interfaces(script)

	if implements.is_empty():
		return false

	for i in interfaces:
		var implementation_id: String = _get_identifier(script)
		var interface_id: String = _get_identifier(i)

		if validate:
			if not _validate(script, i, assert_on_fail):
				return false
		else:
			if i not in implements:
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
func implementations(objects: Array, interfaces, validate = false) -> Array:
	var result = []

	for object in objects:
		if implements(object, interfaces, validate):
			result.append(object)

	return result


func _init():
	if OS.has_feature("editor"):
		# print('Global Class List:')
		# print(_global_class_list)
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
		var interfaces = _get_interfaces(script)

		if not interfaces.is_empty():
			implements(script, interfaces, strict_validation, true)


func _get_all_files(path: String) -> PackedStringArray:
	var cur_dir := DirAccess.open(path)
	if not cur_dir:
		printerr("An error occurred when trying to access '%s'." % [path])
		return []

	cur_dir.include_navigational = false  # ignore '.' and '..'
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

		var path_tokens = d.split("/")
		var dir_name = path_tokens[path_tokens.size() - 1]
		if dir_name not in IGNORE_DIRS:
			var nfiles := cur_dir.get_files()
			for j in range(nfiles.size()):
				nfiles[j] = cur_dir.get_current_dir().path_join(nfiles[j])
			files.append_array(nfiles)

			var ndirs := cur_dir.get_directories()
			for j in range(ndirs.size()):
				ndirs[j] = cur_dir.get_current_dir().path_join(ndirs[j])
			dirs.append_array(ndirs)
		i += 1

	return files


func _column(rows: Array, key: String) -> Array:
	var result := []

	for row in rows:
		result.append(row.get(key))

	return result


func _get_script(implementation) -> GDScript:	# ?
	if not implementation is GDScript:
		return implementation.get_script()

	return implementation


# Retrieve implementation's _implements_ const objects.
func _get_interfaces(implementation: Resource) -> Array:
	var script: GDScript = _get_script(implementation)
	var lookup: String = str(script)

	if _implements.has(lookup):
		return _implements[lookup]

	_implements[lookup] = []
	# Get implements constant from script
	var consts: Dictionary = script.get_script_constant_map()

	if consts.has("implements"):
		var interfaces: Array[GDScript] = []

		for interface in consts["implements"]:
			var obj: GDScript = null
			if interface is String:
				assert(allow_string_classes, "Cannot use string type in implements as 'allow_string_classes' is false. ('%s' in %s)" % [interface, lookup])
				obj = _get_interface_script(interface)
			elif interface is GDScript:
				obj = interface

			if strict_interface_name:
				assert(obj.get_global_name().begins_with("I"), "Interface '%s' not starts with 'I' (Path: '%s')." % [obj.get_global_name(), script.resource_path])
				assert(interface in _global_class_names, "Interface '%s' not found in global class list. Check if declaration is correct in '%s'." % [interface, script.resource_path])
			# WARN: Collateral effect on release mode, the asserts will be stripped out
			# and the execution will follow
			interfaces.append(obj)

		_implements[lookup] = interfaces

	return _implements[lookup]

# interface: [String]
# https://gamedev.stackexchange.com/questions/208348/is-there-a-way-to-instantiate-a-custom-class-decided-at-runtime-in-gdscript
func _get_interface_script(interface_name: String) -> GDScript:
	# TODO: Make memoization? Already happens at the parent.
	#if _interface_objs.has(interface_name):
		#return _interface_objs[interface_name]

	var obj: GDScript = null
	# Checks if script is already loaded
	if ResourceLoader.exists(interface_name, "Script"):
		obj = load(interface_name)
	# Tries to load de script
	# NOTE: Probably can be optimized sorting the global_class_name array and doing
	# a binary search. If 'interface_name' exists retrieve 'path' from global_class_list.
	# Maybe will be necessary to map clas_name -> obj to make this work.
	for global_class in _global_class_list:
		if interface_name == global_class["class"]:
			var interface_path: String = global_class["path"]
			obj = load(interface_path)

	#_interfaces_objs[interface_name] = obj
	return obj

# Get class name from 'script'
func _get_identifier(implementation, strict = false) -> String:
	var script: GDScript = _get_script(implementation)
	var lookup: String = str(script)

	if _identifiers.has(lookup):
		return _identifiers[lookup]

	# Extract class_name from script
	if script.has_source_code():
		var regex: RegEx = RegEx.new()
		regex.compile("class_name\\s+(\\w+)")
		var result = regex.search(script.source_code)

		if result:
			_identifiers[lookup] = result.get_string(1)
		else:
			_identifiers[lookup] = "" if strict else script.resource_path

		return _identifiers[lookup]

	return "Unknown"

func _validate_implementation(script: GDScript, interface: GDScript, assert_on_fail = false) -> bool:
	var implementation_id = _get_identifier(script)
	var interface_id = _get_identifier(interface)

	if not interface.has_source_code():
		return true
	elif not script.has_source_code():
		if assert_on_fail:
			assert(false, "'%s' doesnt implement '%s'. As it not has a script." % [implementation_id, interface_id])
		else:
			return false

	print(interface.get_global_name())
	# NOTE: As this is a 'GDScript', inherits properties from the parent.
	# We can remove inherited properties and validated only the ones added
	# by the user.
	#print(interface.get_property_list())
	#print()
	#assert(interface.get_property_list().is_empty(), "Interface with properties.")
	print(interface.get_script_constant_map())
	assert(interface.get_script_constant_map().is_empty(), "Interface with constants.")

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

## Validates 'implementation' of 'interface'.
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
