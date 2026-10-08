extends RefCounted
## Preferência visual persistente; não modifica mecânicas nem troca o renderer em execução.
const NAMES := ["mobile", "balanced", "ultra"]
const LABELS := ["Gráficos: Leve", "Gráficos: Equilibrado", "Gráficos: Alto"]

static func selected() -> String:
	var cfg := ConfigFile.new()
	cfg.load("user://visual.cfg")
	var value := String(cfg.get_value("graphics", "quality", "mobile" if OS.has_feature("mobile") else "balanced"))
	return value if value in NAMES else "balanced"

static func save(value: String) -> void:
	if value not in NAMES:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", value)
	cfg.save("user://visual.cfg")
