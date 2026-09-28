package;

/**
 * Skill/Status remaining time reader from SolarFlare.
 * 7-rung ladder for robust remaining time detection.
 */
class SkillRemain {
	public static inline var INFINITE_LEFT:Float = -1;
	static inline var MAX_FINITE_LEFT:Float = 3600;

	static var PACK:Array<String> = [
		"remaining", "timeLeft", "durationLeft", "elapsed", "cdUntil", "progress"
	];

	static var lastResult:SkillRemainResult = new SkillRemainResult();

	static inline var RUNG_STATUS:Int = 0;
	static inline var RUNG_TYPED:Int = 1;
	static inline var RUNG_ELAPSED:Int = 2;
	static inline var RUNG_INFO:Int = 3;
	static inline var RUNG_WALK:Int = 4;
	static inline var RUNG_INF:Int = 5;
	static inline var RUNG_RESOLVED:Int = 6;
	static inline var RUNG_COUNT:Int = 7;
	static inline var RUNG_MEMO_CAP:Int = 48;

	static var rungByType:Map<String, Int> = new Map();

	public static function read(item:Dynamic):SkillRemainResult {
		if (item == null)
			return miss();
		var typeName:String = FieldWalk.liveTypeName(item);
		var keyed = typeName != null && typeName.length > 0;
		var start = -1;
		if (keyed) {
			var memo = rungByType.get(typeName);
			if (memo != null)
				start = memo;
		}
		if (start > 0) {
			var hit = tryRung(item, start);
			if (hit != null)
				return hit;
		}
		var i = 0;
		while (i < RUNG_COUNT) {
			if (i != start) {
				var hit = tryRung(item, i);
				if (hit != null) {
					if (keyed && (start < 0 || i < start) && countMapKeys(rungByType) < 48)
						rungByType.set(typeName, i);
					return hit;
				}
			}
			i++;
		}
		return miss();
	}

	static function tryRung(item:Dynamic, rung:Int):SkillRemainResult {
		switch (rung) {
			case 0: return statusRemain(item);
			case 1: return typedRemain(item);
			case 2: return elapsedRemain(item);
			case 3: return infoRemain(item);
			case 4: return walkRemain(item);
			case 5: {
				var inf = FieldWalk.extractObject(item, "inf");
				if (inf != null) {
					var r = walkRemain(inf);
					if (usable(r)) return r;
				}
			}
			case 6: return resolvedRemain(item);
		}
		return null;
	}

	static function usable(r:SkillRemainResult):Bool {
		return r != null && r.valid;
	}

	static function miss():SkillRemainResult {
		return lastResult.set(1, 0, false, false);
	}

	/** Status-first path matching EventHorizon AuraTracker candidates. */
	static function statusRemain(item:Dynamic):SkillRemainResult {
		try {
			var dur = 0.0;
			try dur = FieldWalk.extractNumber(item, "duration") catch (_:Dynamic) dur = 0;
			if (dur <= 0.05) {
				return lastResult.set(1, -1, true, true);
			}
			var left = 0.0;
			var gotLeft = false;
			try {
				left = Reflect.field(item, "getDurationLeft")();
				gotLeft = true;
			} catch (_:Dynamic)
				left = 0;
			var prog = Math.NaN;
			try
				prog = Reflect.field(item, "getDurationProgress")()
			catch (_:Dynamic)
				prog = Math.NaN;
			var progLive = !Math.isNaN(prog) && prog > 0.001 && prog < 0.999;
			var max = dur;
			if (max <= 0.05 && !progLive) {
				try {
					var info = Reflect.field(item, "getStatusInfo")();
					if (info != null) {
						var d:Float = FieldWalk.extractNumber(info, "duration");
						if (d > 0.05)
							max = d;
					}
				} catch (_:Dynamic) {}
			}
			if (gotLeft && left <= 0.02 && max > 0.05) {
				return lastResult.set(0, left < 0 ? 0 : left, true, false);
			}
			return finish(left, prog, max, false);
		} catch (_:Dynamic) {}
		return miss();
	}

	static function typedRemain(item:Dynamic):SkillRemainResult {
		try {
			var dur = 0.0;
			try dur = FieldWalk.extractNumber(item, "duration") catch (_:Dynamic) dur = 0;
			if (dur <= 0.05) {
				return lastResult.set(1, -1, true, true);
			}
			var left = 0.0;
			var gotLeft = false;
			try {
				left = Reflect.field(item, "getDurationLeft")();
				gotLeft = true;
			} catch (_:Dynamic)
				left = 0;
			var prog = Math.NaN;
			try
				prog = Reflect.field(item, "getDurationProgress")()
			catch (_:Dynamic)
				prog = Math.NaN;
			if (gotLeft && left <= 0.02 && dur > 0.05)
				return lastResult.set(0, left < 0 ? 0 : left, true, false);
			return finish(left, prog, dur, false);
		} catch (_:Dynamic) {}
		return miss();
	}

	static function elapsedRemain(item:Dynamic):SkillRemainResult {
		var elapsed = callFloat(item, "getElapsedTime");
		var max = callFloat(item, "getBaseDuration");
		if (!(max > 0.05))
			max = callFloat(item, "evalDuration");
		if (!(max > 0.05) || Math.isNaN(elapsed) || elapsed < 0)
			return miss();
		var left = max - elapsed;
		if (left < 0)
			left = 0;
		return finish(left, left / max, max, false);
	}

	static function infoRemain(item:Dynamic):SkillRemainResult {
		try {
			var info = Reflect.field(item, "getStatusInfo")();
			if (info == null)
				return miss();
			return walkRemain(info);
		} catch (_:Dynamic) {}
		return miss();
	}

	static function walkRemain(obj:Dynamic):SkillRemainResult {
		if (obj == null)
			return miss();
		var left = FieldWalk.extractNumberAny(obj, ["remaining", "timeLeft", "durationLeft", "elapsed", "cdUntil", "progress"], -1);
		var max = FieldWalk.extractNumber(obj, "duration", 0);
		if (!(max > 0.05))
			max = FieldWalk.extractNumber(obj, "baseDuration", 0);
		if (!(left > 0) && max > 0.05) {
			var elapsed = FieldWalk.extractNumber(obj, "elapsed", Math.NaN);
			if (!Math.isNaN(elapsed) && elapsed >= 0)
				left = max - elapsed;
		}
		var until = FieldWalk.extractNumber(obj, "cdUntil", -1);
		if (until > 100) {
			var now = gameNow();
			if (now > 0 && until > now)
				left = until - now;
		}
		var prog = FieldWalk.extractNumber(obj, "progress", Math.NaN);
		if (Math.isNaN(prog))
			prog = FieldWalk.extractNumber(obj, "durationProgress", Math.NaN);
		return finish(left, prog, max, false);
	}

	static function resolvedRemain(item:Dynamic):SkillRemainResult {
		var left = callFloat(item, "getDurationLeft");
		var prog = callFloat(item, "getDurationProgress");
		var max = callFloat(item, "getBaseDuration");
		if (!(max > 0.05))
			max = callFloat(item, "evalDuration");
		if (!(left > 0) && max > 0.05) {
			var elapsed = callFloat(item, "getElapsedTime");
			if (!Math.isNaN(elapsed) && elapsed >= 0)
				left = max - elapsed;
		}
		return finish(left, prog, max, false);
	}

	static function finish(left:Float, prog:Float, max:Float, infinite:Bool):SkillRemainResult {
		if (infinite)
			return lastResult.set(1, -1, true, true);
		var l = left;
		if (Math.isNaN(l) || l < 0)
			l = 0;
		if (l > 3600)
			return lastResult.set(1, -1, true, true);
		var p = prog;
		if (Math.isNaN(p) || p < 0 || p > 1.01) {
			if (max > 0.05 && l >= 0)
				p = l / max;
			else if (l > 0.05)
				p = 1;
			else
				p = 0;
		}
		if (p > 1)
			p = 1;
		if (p < 0)
			p = 0;
		var valid = l > 0.02 || (p > 0.001 && p < 0.999);
		if (!valid)
			return miss();
		return lastResult.set(p, l, true, false);
	}

	static function countMapKeys(m:Map<String, Int>):Int {
		var c = 0;
		for (_ in m)
			c++;
		return c;
	}

	static function callFloat(item:Dynamic, method:String):Float {
		if (item == null)
			return Math.NaN;
		try {
			var v:Dynamic = Reflect.field(item, method);
			if (v != null && Reflect.isFunction(v)) {
				var f:Float = v();
				if (!Math.isNaN(f))
					return f;
			}
		} catch (_:Dynamic) {}
		var n = FieldWalk.extractNumber(item, method, Math.NaN);
		return n;
	}

	static function gameNow():Float {
		try {
			var timerClass = Type.resolveClass("hxd.Timer");
			if (timerClass != null) {
				var t = Reflect.field(timerClass, "lastTimeStamp");
				if (t != null && (t:Float) > 0)
					return t;
			}
		} catch (_:Dynamic) {}
		try {
			var timerClass = Type.resolveClass("hxd.Timer");
			if (timerClass != null) {
				var t = Reflect.field(timerClass, "elapsedTime");
				if (t != null && (t:Float) > 0)
					return t;
			}
		} catch (_:Dynamic) {}
		try
			return haxe.Timer.stamp()
		catch (_:Dynamic)
			return Date.now().getTime() / 1000.0;
	}
}

/** Reused by SkillRemain.read — copy fields before the next read. */
class SkillRemainResult {
	public var progress:Float = 1;
	public var left:Float = 0;
	public var valid:Bool = false;
	public var infinite:Bool = false;

	public function new() {}

	public function set(progress:Float, left:Float, valid:Bool, infinite:Bool):SkillRemainResult {
		this.progress = progress;
		this.left = left;
		this.valid = valid;
		this.infinite = infinite;
		return this;
	}
}