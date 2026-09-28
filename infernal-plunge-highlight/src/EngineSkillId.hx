package;

/**
 * Skill ID resolution from SolarFlare - robust skill identification.
 */
class EngineSkillId {
	static var ready:Bool = false;
	static var hashToScript:Map<String, String> = new Map();
	static var displayCache:Map<String, String> = new Map();

	public static function keep():Void {
		ensure();
	}

	/** Full engine id, or "" if not confirmed. */
	public static function display(id:String):String {
		if (id == null || id.length == 0)
			return "";
		var cached = displayCache.get(id);
		if (cached != null)
			return cached;
		ensure();
		var s = clean(id);
		var result = "";
		if (s.length > 0) {
			var mapped = hashToScript.get(s);
			if (mapped != null && mapped.length > 0)
				result = mapped;
			else if (isScriptStyle(s))
				result = s;
		}
		displayCache.set(id, result);
		return result;
	}

	public static function ofSkill(skill:Dynamic):String {
		if (skill == null)
			return "";
		try {
			var access:Dynamic = skill;
			var id = Reflect.field(access, "get_skillId");
			if (id != null && Reflect.isFunction(id)) {
				var shown = display(id());
				if (shown.length > 0) {
					return shown;
				}
			}
		} catch (_:Dynamic) {}
		try {
			var bs:Dynamic = skill;
			var shown = display(FieldWalk.extractString(bs, "kind"));
			if (shown.length > 0) {
				return shown;
			}
			var inf = FieldWalk.extractObject(bs, "inf");
			if (inf != null) {
				shown = display(FieldWalk.extractString(inf, "id"));
				if (shown.length > 0) {
					return shown;
				}
			}
		} catch (_:Dynamic) {}
		var kind = FieldWalk.extractString(skill, "kind");
		var shown = display(kind);
		if (shown.length > 0) {
			return shown;
		}
		var inf = FieldWalk.extractObject(skill, "inf");
		shown = display(FieldWalk.extractString(inf, "id"));
		if (shown.length > 0) {
			return shown;
		}
		shown = display(FieldWalk.extractString(inf, "script"));
		if (shown.length > 0) {
			return shown;
		}
		shown = display(FieldWalk.extractString(skill, "id"));
		return shown;
	}

	static function ensure():Void {
		// Add known skill IDs here if needed
	}

	static function pin(scriptId:String):Void {
		if (scriptId != null && scriptId.length > 0)
			hashToScript.set(scriptId, scriptId);
	}

	static function isScriptStyle(s:String):Bool {
		if (s.length < 3)
			return false;
		if (s.indexOf("_") < 0)
			return false;
		return isClean(s);
	}

	static function clean(id:String):String {
		if (id == null)
			return "";
		var s = StringTools.trim(id);
		if (s.length < 3)
			return "";
		if (!isClean(s))
			return "";
		return s;
	}

	static function isClean(s:String):Bool {
		if (s == null || s.length == 0)
			return false;
		if (s.indexOf("{") >= 0 || s.indexOf("}") >= 0)
			return false;
		if (s.indexOf("bytes") >= 0 || s.indexOf("Bytes") >= 0)
			return false;
		if (s.indexOf("haxe.io") >= 0 || s.indexOf("haxe.Io") >= 0)
			return false;
		return true;
	}
}