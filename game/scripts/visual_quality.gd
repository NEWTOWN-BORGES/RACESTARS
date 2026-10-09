extends RefCounted
## Preferência visual persistente; não modifica mecânicas nem troca o renderer em execução.
const NAMES := ["stable", "mobile", "balanced", "ultra"]
const LABELS := ["Gráficos: A15 (30 FPS)", "Gráficos: Leve", "Gráficos: Equilibrado", "Gráficos: Alto"]

static func is_a15_model(model: String) -> bool:
	var name := model.to_lower()
	return name.begins_with("sm-a155") or name.begins_with("sm-a156") or "galaxy a15" in name

static func selected() -> String:
	var cfg := ConfigFile.new()
	cfg.load("user://visual.cfg")
	var value := String(cfg.get_value("graphics", "quality", "mobile" if OS.has_feature("mobile") else "balanced"))
	# A primeira atualização num A15 migra Leve para Estável. Uma escolha manual
	# posterior continua a ser respeitada, inclusive se voltar a escolher Leve.
	if OS.has_feature("android") and is_a15_model(OS.get_model_name()) and not cfg.get_value("graphics", "a15_profile_seen", false):
		if value == "mobile":
			value = "stable"
		cfg.set_value("graphics", "quality", value)
		cfg.set_value("graphics", "a15_profile_seen", true)
		cfg.save("user://visual.cfg")
	return value if value in NAMES else "balanced"

static func save(value: String) -> void:
	if value not in NAMES:
		return
	var cfg := ConfigFile.new()
	cfg.load("user://visual.cfg")
	cfg.set_value("graphics", "quality", value)
	cfg.set_value("graphics", "a15_profile_seen", true)
	cfg.save("user://visual.cfg")
