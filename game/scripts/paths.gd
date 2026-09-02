class_name Paths
## Asset root resolution for both layouts: the dev tree (the game/ project
## sits beside assets/) and an exported build, where setup.exe puts
## everything it generates under _build/ beside the exe (_build/assets).
## Every filesystem asset access goes through here.

static func root() -> String:
	if OS.has_feature("editor"):
		var proj := ProjectSettings.globalize_path("res://")
		if proj.ends_with("/"):
			proj = proj.substr(0, proj.length() - 1)
		return proj.get_base_dir().path_join("assets")
	return OS.get_executable_path().get_base_dir().path_join("_build") \
			.path_join("assets")


static func asset(rel: String) -> String:
	return root().path_join(rel)
