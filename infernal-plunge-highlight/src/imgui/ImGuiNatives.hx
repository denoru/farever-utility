package imgui;

class ImGuiNatives {
	@:hlNative("imgui", "claim_present_hook")
	public static function claimPresentHook():Bool {
		return false;
	}

	@:hlNative("imgui", "register")
	public static function register(name:hl.Bytes, draw:Void->Void):Void {}

	@:hlNative("imgui", "unregister")
	public static function unregister(name:hl.Bytes):Void {}

	@:hlNative("imgui", "igBegin_Ptr")
	public static function igBeginPtr(label:hl.Bytes, pOpen:hl.Bytes, flags:Int):Bool {
		return false;
	}

	@:hlNative("imgui", "igEnd")
	public static function igEnd():Void {}

	@:hlNative("imgui", "igSetNextWindowBgAlpha")
	public static function igSetNextWindowBgAlpha(alpha:Single):Void {}

	@:hlNative("imgui", "igPushStyleColor_U32")
	public static function igPushStyleColorU32(idx:Int, col:Int):Void {}

	@:hlNative("imgui", "igPopStyleColor")
	public static function igPopStyleColor(count:Int):Void {}

	@:hlNative("imgui", "igTextUnformatted")
	public static function igTextUnformatted(text:hl.Bytes, textEnd:hl.Bytes):Void {}

	@:hlNative("imgui", "igSeparator")
	public static function igSeparator():Void {}

	@:hlNative("imgui", "igSameLine")
	public static function igSameLine(offset:Single, spacing:Single):Void {}
}
