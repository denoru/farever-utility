package;

import haxe.macro.Context;
import Reflect;
import Type;
import Std;
import Math;

/**
 * Minimal FieldWalk from SolarFlare - safe field extraction from Dynamic objects.
 */
class FieldWalk {
	
	public static function extractObject(obj:Dynamic, name:String):Dynamic {
		if (obj == null || name == null)
			return null;
		try {
			return Reflect.field(obj, name);
		} catch (_:Dynamic)
			return null;
	}
	
	public static function extractString(obj:Dynamic, name:String, fallback:String = ""):String {
		if (obj == null || name == null)
			return fallback;
		try {
			var v:Dynamic = Reflect.field(obj, name);
			if (v != null && Std.isOfType(v, String))
				return v;
		} catch (_:Dynamic) {}
		return fallback;
	}
	
	public static function extractNumber(obj:Dynamic, name:String, fallback:Float = 0):Float {
		if (obj == null || name == null)
			return fallback;
		try {
			var v:Dynamic = Reflect.field(obj, name);
			if (v != null) {
				var f:Float = v;
				if (!Math.isNaN(f))
					return f;
			}
		} catch (_:Dynamic) {}
		return fallback;
	}
	
	public static function extractNumberAny(obj:Dynamic, names:Array<String>, fallback:Float = 0):Float {
		if (obj == null || names == null)
			return fallback;
		var i = 0;
		while (i < names.length) {
			var v = extractNumber(obj, names[i], Math.NaN);
			if (!Math.isNaN(v))
				return v;
			i++;
		}
		return fallback;
	}
	
	public static function liveTypeName(obj:Dynamic):String {
		if (obj == null)
			return "";
		try {
			var t:Class<Dynamic> = Type.getClass(obj);
			if (t != null)
				return Type.getClassName(t);
		} catch (_:Dynamic) {}
		return "";
	}
}