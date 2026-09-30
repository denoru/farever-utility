import HlxRuntime;
import hlx.runtime.ResolvedMember;
import imgui.ImGui;
import imgui.Enums.ImGuiWindowFlags;
import imgui.Enums.ImGuiCol;
import imgui.Enums.ImGuiKey;
import imgui.Enums.ImGuiInputTextFlags;
import imgui.ref.BoolRef;
import imgui.ref.IntRef;

typedef CastSequenceConfig = {
	var enabled:Bool;
	var triggerKey:Int;
	var editorOpen:Bool;
	var steps:Array<String>;
	var mode:String;
	var hotkeys:String;
	var stepDelayMs:Int;
	var strictOrder:Bool;
	var plungeNeedsMark:Bool;
}

@:build(hlx.runtime.Mod.build())
class Main {
	static final ADD_BUF_SIZE = 128;
	static final HK_BUF_SIZE = 128;
	static final DEFAULT_HOTKEYS = "R>2>E>Q>G>3>2>1>T>2>1>T>2>T";
	static final DEFAULT_INJECTOR = "C:/Program Files (x86)/Steam/steamapps/common/Farever/hlx/mods/cast-sequence/injector.exe";
	static final PLUNGE_KIND = "Daggers_Demondash_Skill1"; // Infernal Plunge
	static final MARK_STATUSES = ["Daggers_Demondash_Mark", "Status_Chaos_Mark", "Chaos_Mark"];

	static final KEY_NAMES = [
		"Space", "Tab", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
		"Mouse X1", "Mouse X2"
	];
	static final KEY_VALUES = [
		ImGuiKey.Space, ImGuiKey.Tab,
		ImGuiKey.F1, ImGuiKey.F2, ImGuiKey.F3, ImGuiKey.F4, ImGuiKey.F5, ImGuiKey.F6,
		ImGuiKey.F7, ImGuiKey.F8, ImGuiKey.F9, ImGuiKey.F10, ImGuiKey.F11, ImGuiKey.F12,
		ImGuiKey.MouseX1, ImGuiKey.MouseX2
	];

	@:hlx.config
	public static var config(default, null):CastSequenceConfig = {
		enabled: true,
		triggerKey: ImGuiKey.F1,
		editorOpen: true,
		steps: [],
		mode: "skill",
		hotkeys: DEFAULT_HOTKEYS,
		stepDelayMs: 300,
		strictOrder: true,
		plungeNeedsMark: true
	};

	static var lastHotkeyAt:Float = 0;

	static function stepDelayMsOrDefault():Int {
		var v:Null<Int> = config.stepDelayMs;
		if (v == null) return 300;
		return v < 0 ? 0 : v;
	}

	// strict order: each trigger press casts ONLY the cursor step and never
	// skips ahead; a missing saved value counts as ON
	static function strictOn():Bool {
		return config.strictOrder != false;
	}

	// Infernal Plunge only fires on a Chaos-Marked target; missing value = ON
	static function plungeGateOn():Bool {
		return config.plungeNeedsMark != false;
	}

	static var hkBuf:hl.Bytes = null;

	// ---------------------------------------------------------------- hotkey mode

	static function isHotkeyMode():Bool {
		return config.mode == "hotkey";
	}

	static function hotkeySeq():String {
		return config.hotkeys == null ? DEFAULT_HOTKEYS : config.hotkeys;
	}

	static var hkCacheSrc:String = null;
	static var hkCache:Array<String> = [];

	static function hotkeyList():Array<String> {
		var src = hotkeySeq();
		if (hkCacheSrc != src) {
			hkCacheSrc = src;
			hkCache = [];
			for (part in src.split(">")) {
				var t = StringTools.trim(part);
				if (t != "") hkCache.push(t);
			}
		}
		return hkCache;
	}

	// tokens: single letter/digit = keyboard key; T / MB1 / M4 / X1 = mouse back; MB2 / M5 / X2 = mouse forward
	static function classify(tok:String):Array<String> {
		var t = StringTools.trim(tok).toUpperCase();
		if (t == "T" || t == "MB1" || t == "MB4" || t == "M4" || t == "MX1" || t == "X1" || t == "MOUSEBACK")
			return ["mouse", "x1"];
		if (t == "MB2" || t == "MB5" || t == "M5" || t == "MX2" || t == "X2" || t == "MOUSEFWD")
			return ["mouse", "x2"];
		if (t.length == 1) {
			var c = t.charCodeAt(0);
			if ((c >= 65 && c <= 90) || (c >= 48 && c <= 57)) return ["key", t];
		}
		return null;
	}

	static var injectorPath:String = null;
	static var injectorMissing = false;
	static var injProc:sys.io.Process = null;
	static var injStartFailed = false;

	static function injectorExe():String {
		if (injectorMissing) return null;
		if (injectorPath != null) return injectorPath;
		var cands = ["mods/cast-sequence/injector.exe", "hlx/mods/cast-sequence/injector.exe"];
		try {
			var p = Sys.programPath();
			if (p != null && p != "") {
				var d = haxe.io.Path.directory(p);
				if (d != "") {
					cands.push(d + "/mods/cast-sequence/injector.exe");
					cands.push(d + "/hlx/mods/cast-sequence/injector.exe");
				}
			}
		} catch (e:Dynamic) {}
		cands.push(DEFAULT_INJECTOR);
		for (c in cands) {
			try {
				if (sys.FileSystem.exists(c)) {
					injectorPath = c;
					return c;
				}
			} catch (e:Dynamic) {}
		}
		trace("injector.exe not found (tried " + cands.length + " paths)");
		injectorMissing = true;
		return null;
	}

	static function startInjector():Bool {
		if (injProc != null) return true;
		if (injStartFailed) return false;
		var exe = injectorExe();
		if (exe == null) {
			injStartFailed = true;
			return false;
		}
		try {
			injProc = new sys.io.Process(exe, []);
			trace("injector: started " + exe);
			return true;
		} catch (e:Dynamic) {
			trace("injector start failed: " + e);
			injProc = null;
			injStartFailed = true;
			return false;
		}
	}

	static function pressToken(tok:String):Bool {
		var args = classify(tok);
		if (args == null) {
			trace("hotkey: invalid token '" + tok + "'");
			return false;
		}
		var line = args[0] + " " + args[1] + "\n";
		if (!startInjector()) return false;
		try {
			injProc.stdin.writeString(line);
			injProc.stdin.flush();
			return true;
		} catch (e:Dynamic) {
			trace("injector write failed: " + e + ", restarting");
			try injProc.close() catch (_:Dynamic) {}
			injProc = null;
			injStartFailed = false;
			if (!startInjector()) return false;
			try {
				injProc.stdin.writeString(line);
				injProc.stdin.flush();
				return true;
			} catch (e2:Dynamic) {
				trace("injector retry failed: " + e2);
				return false;
			}
		}
	}

	static var cursor:Int = 0;
	static var resolved:Bool = false;
	static var resolveFailed:Bool = false;

	static var rmCtrl:ResolvedMember;       // getMyController (static or instance on GameApp)
	static var rmGetSkill:ResolvedMember;   // ent.GameObject.getSkill(kind)
	static var rmTryUse:ResolvedMember;     // client.UnitController.tryUseSkill(skill, target)
	static var rmDoUse:ResolvedMember;      // ent.Hero.doUseSkill(skill, target, item)
	static var rmCdLeft:ResolvedMember;      // st.skill.Skill.getCooldownLeft()
	static var rmCharges:ResolvedMember;     // st.skill.Skill.getCurrentCharges()
	static var rmMaxCharges:ResolvedMember;  // st.skill.Skill.getMaxCharges()
	static var rmIsIn:ResolvedMember;        // st.skill.Skill.isInCooldown()
	static var rmEffSkill:ResolvedMember;    // st.skill.Skill.getEffectiveSkill()
	static var rmPhase:ResolvedMember;       // st.skill.Skill.get_phase()
	static var rmCheckUse:ResolvedMember;    // st.skill.Skill.checkUse(...)
	static var skillTargetVal:Dynamic;      // st.skill.SkillTarget.Target value
	static var skillTargetFactory:Dynamic;  // Target ctor factory (ent.GameObject) -> SkillTarget, when exposed as one

	static var addBuf:hl.Bytes = null;
	static var imguiRegistered:Bool = false;
	static var imguiInitAttempted:Bool = false;
	static var probed:Bool = false;

	static function main():Void {
		if (addBuf == null) addBuf = new hl.Bytes(ADD_BUF_SIZE);
		if (hkBuf == null) {
			hkBuf = new hl.Bytes(HK_BUF_SIZE);
			fillBuf(hkBuf, HK_BUF_SIZE, hotkeySeq());
		}
		ensureImGui();
		if (isHotkeyMode()) startInjector();
	}

	// ---------------------------------------------------------------- reflection

	static function ensureResolved():Bool {
		if (resolved) return true;
		if (resolveFailed) return false;

		var tApp = HlxRuntime.resolveType("GameApp");
		var tGo = HlxRuntime.resolveType("ent.GameObject");
		var tCtrl = HlxRuntime.resolveType("client.UnitController");
		var tHero = HlxRuntime.resolveType("ent.Hero");
		var tSkill = HlxRuntime.resolveType("st.skill.Skill");

		if (tApp == null || tGo == null || tSkill == null) {
			resolveFailed = true;
			trace("resolve failed: app=" + (tApp != null) + " go=" + (tGo != null) + " skill=" + (tSkill != null));
			return false;
		}

		rmCtrl = HlxRuntime.resolveStaticMember(tApp, "getMyController");
		if (rmCtrl == null) rmCtrl = HlxRuntime.resolveMember(tApp, "getMyController");
		rmGetSkill = HlxRuntime.resolveMember(tGo, "getSkill");
		if (tCtrl != null) rmTryUse = HlxRuntime.resolveMember(tCtrl, "tryUseSkill");
		if (tHero != null) rmDoUse = HlxRuntime.resolveMember(tHero, "doUseSkill");
		rmCdLeft = HlxRuntime.resolveMember(tSkill, "getCooldownLeft");
		rmCharges = HlxRuntime.resolveMember(tSkill, "getCurrentCharges");
		rmMaxCharges = HlxRuntime.resolveMember(tSkill, "getMaxCharges");
		rmIsIn = HlxRuntime.resolveMember(tSkill, "isInCooldown");
		rmEffSkill = HlxRuntime.resolveMember(tSkill, "getEffectiveSkill");
		rmPhase = HlxRuntime.resolveMember(tSkill, "get_phase");
		rmCheckUse = HlxRuntime.resolveMember(tSkill, "checkUse");

		var tTarget = HlxRuntime.resolveType("st.skill.SkillTarget");
		if (tTarget != null) {
			try {
				var v:Dynamic = null;
				try v = HlxRuntime.resolveStaticField(tTarget, "Target")
				catch (e:Dynamic) trace("target: resolveStaticField error: " + e);
				if (v != null) {
					// enum ctor fn doubles as a factory: f(unit) -> Target(unit)
					skillTargetFactory = v;
					trace("target: factory = ctor fn");
				} else {
					try v = HlxRuntime.constructEnum(tTarget, "Target", [])
					catch (e:Dynamic) trace("target: constructEnum(0) error: " + e);
					if (v == null) {
						try v = HlxRuntime.constructEnum(tTarget, "Target", [null])
						catch (e:Dynamic) trace("target: constructEnum(1) error: " + e);
					}
					skillTargetVal = v;
				}
				var vtn = "null";
				if (skillTargetVal != null) {
					try vtn = hl.Type.getDynamic(skillTargetVal).getTypeName() catch (_:Dynamic) {}
				}
				trace("target value type=" + vtn);
			} catch (e:Dynamic) {
				trace("target block error: " + e);
			}
		}

		resolved = true;
		trace("resolved: ctrl=" + (rmCtrl != null) + " getSkill=" + (rmGetSkill != null)
			+ " tryUse=" + (rmTryUse != null) + " doUse=" + (rmDoUse != null)
			+ " cdLeft=" + (rmCdLeft != null) + " charges=" + (rmCharges != null && rmMaxCharges != null)
			+ " inCd=" + (rmIsIn != null) + " eff=" + (rmEffSkill != null)
			+ " phase=" + (rmPhase != null) + " chk=" + (rmCheckUse != null)
			+ " targetEnum=" + (skillTargetVal != null));
		return true;
	}

	static function getApp():Dynamic {
		try {
			var tApp = HlxRuntime.resolveType("GameApp");
			if (tApp != null) {
				var rmGet = HlxRuntime.resolveMember(tApp, "get");
				if (rmGet != null) {
					var app = HlxRuntime.callResolved(rmGet, []);
					if (app != null) return app;
				}
			}
		} catch (_:Dynamic) {}
		return null;
	}

	static function getHero():Dynamic {
		var app = getApp();
		if (app != null) {
			var hero = Reflect.field(app, "hero");
			if (hero != null) return hero;
		}
		return null;
	}

	static function getController():Dynamic {
		if (rmCtrl != null) {
			try {
				var c = HlxRuntime.callResolved(rmCtrl, []);
				if (c != null) return c;
			} catch (_:Dynamic) {}
			var app = getApp();
			if (app != null) {
				try {
					var c = HlxRuntime.callResolved(rmCtrl, [app]);
					if (c != null) return c;
				} catch (_:Dynamic) {}
			}
		}
		return null;
	}

	static var renameCache = new Map<String, String>();

	static function skillOf(kind:String):Dynamic {
		if (!ensureResolved()) return null;
		var hero = getHero();
		if (hero == null || rmGetSkill == null) return null;
		var sk:Dynamic = null;
		try sk = HlxRuntime.callResolved(rmGetSkill, [hero, kind]) catch (_:Dynamic) {}
		if (sk != null) return sk;
		var cached = renameCache.get(kind);
		if (cached != null && cached != kind) {
			try sk = HlxRuntime.callResolved(rmGetSkill, [hero, cached]) catch (_:Dynamic) {}
			if (sk != null) return sk;
		}
		var found = scanSlots(kind);
		if (found != null) {
			renameCache.set(kind, found.kind);
			trace("skillOf: " + kind + " missing; resolved via slot kind " + found.kind);
			return found.skill;
		}
		return null;
	}

	// Walk hero skill collections looking for kind (exact, then renamed variant
	// like "<kind>_Throw"). Digit-suffix collisions (Skill1 vs Skill10) excluded.
	static function scanSlots(kind:String):Dynamic {
		var hero = getHero();
		if (hero == null) return null;
		var fallback:Dynamic = null;
		for (f in ["attackSkills", "weaponSkills", "skillSlots", "secondarySkill", "dashSkill", "attackComboSkill"]) {
			try {
				var a:Dynamic = Reflect.field(hero, f);
				if (a == null) continue;
				var proxy = Reflect.field(a, "array");
				if (proxy != null) {
					var dynArr = Reflect.field(proxy, "array");
					if (dynArr != null) a = dynArr;
				}
				var getDyn = Reflect.field(a, "getDyn");
				if (getDyn == null) {
					var k0 = fieldStr(a, "kind");
					if (k0 != null && k0 == kind) return {skill: a, kind: k0};
					continue;
				}
				for (i in 0...30) {
					var sk:Dynamic = null;
					try sk = Reflect.callMethod(a, getDyn, [i]) catch (_:Dynamic) {}
					if (sk == null) break;
					var k = fieldStr(sk, "kind");
					if (k == null && Std.isOfType(sk, String)) k = cast sk;
					if (k == null) k = fieldStr(sk, "skillId");
					if (k == null) k = fieldStr(sk, "id");
					if (k == null) continue;
					if (k == kind) return {skill: sk, kind: k};
					if (k.length > kind.length && StringTools.startsWith(k, kind)) {
						var rest = k.charAt(kind.length);
						if (rest != "" && rest < "0" || rest > "9") {
							if (fallback == null) fallback = {skill: sk, kind: k};
						}
					}
				}
			} catch (_:Dynamic) {}
		}
		return fallback;
	}

	static var slotDumpAt:Float = -999;

	static function dumpSlots(label:String):Void {
		var now = haxe.Timer.stamp();
		if (now - slotDumpAt < 1.0) return;
		slotDumpAt = now;
		var hero = getHero();
		if (hero == null) { trace("slots(" + label + "): hero=null"); return; }
		for (f in ["attackSkills", "weaponSkills", "skillSlots", "secondarySkill", "dashSkill", "attackComboSkill"]) {
			try {
				var a:Dynamic = Reflect.field(hero, f);
				if (a == null) continue;
				var proxy = Reflect.field(a, "array");
				if (proxy != null) {
					var dynArr = Reflect.field(proxy, "array");
					if (dynArr != null) a = dynArr;
				}
				var getDyn = Reflect.field(a, "getDyn");
				var parts = new Array<String>();
				var items = new Array<Dynamic>();
				if (getDyn != null) {
					for (i in 0...30) {
						var sk:Dynamic = null;
						try sk = Reflect.callMethod(a, getDyn, [i]) catch (_:Dynamic) {}
						if (sk == null) break;
						items.push(sk);
					}
				} else {
					items.push(a);
				}
				for (sk in items) {
					var k = fieldStr(sk, "kind");
					if (k == null && Std.isOfType(sk, String)) k = cast sk;
					if (k == null) k = fieldStr(sk, "skillId");
					if (k == null) k = fieldStr(sk, "id");
					if (k == null) k = "?";
					var cd = "-";
					if (rmCdLeft != null) {
						try cd = Std.string(HlxRuntime.callResolved(rmCdLeft, [sk])) catch (_:Dynamic) cd = "err";
					}
					parts.push(k + "(" + cd + ")" + diagOf(sk));
				}
				if (parts.length > 0) trace("slots " + label + " " + f + ": " + parts.join(" "));
			} catch (e:Dynamic) trace("slots " + label + " " + f + " error: " + e);
		}
	}

	// -1 = skill not found, -2 = found but cooldown unknown, >= 0 = seconds left
	static function cooldownOf(kind:String):Float {
		var sk = skillOf(kind);
		if (sk == null) {
			dumpSlots("miss:" + kind);
			return -1;
		}
		if (rmCdLeft != null) {
			try {
				var v:Dynamic = HlxRuntime.callResolved(rmCdLeft, [sk]);
				if (v != null) {
					var f:Float = v;
					return f;
				}
			} catch (_:Dynamic) {}
		}
		for (f in ["cooldownLeft", "cdLeft", "cd"]) {
			var v:Dynamic = Reflect.field(sk, f);
			if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) {
				var fv:Float = v;
				return fv;
			}
		}
		return -2;
	}

	// {cur, max} for charge-based skills (e.g. Void Fangs knives), else null
	static function chargeInfo(sk:Dynamic):Dynamic {
		if (sk == null || rmCharges == null || rmMaxCharges == null) return null;
		try {
			var cur:Dynamic = HlxRuntime.callResolved(rmCharges, [sk]);
			var max:Dynamic = HlxRuntime.callResolved(rmMaxCharges, [sk]);
			if (cur == null || max == null) return null;
			var c:Float = cur;
			var m:Float = max;
			return {cur: c, max: m};
		} catch (_:Dynamic) return null;
	}

	static function diagOf(sk:Dynamic):String {
		if (sk == null) return "";
		var ch = chargeInfo(sk);
		var s = ch != null ? " ch=" + Std.string(ch.cur) + "/" + Std.string(ch.max) : " ch=-";
		if (rmIsIn != null) {
			try {
				var b:Dynamic = HlxRuntime.callResolved(rmIsIn, [sk]);
				if (b != null) s += " inCd=" + Std.string(b);
			} catch (_:Dynamic) {}
		}
		if (rmEffSkill != null) {
			try {
				var e:Dynamic = HlxRuntime.callResolved(rmEffSkill, [sk]);
				if (e != null) {
					if (e == sk) s += " eff=self";
					else {
						var ek = fieldStr(e, "kind");
						var ech = chargeInfo(e);
						s += " eff=" + (ek != null ? ek : "?")
							+ (ech != null ? "(" + Std.string(ech.cur) + "/" + Std.string(ech.max) + ")" : "");
					}
				}
			} catch (_:Dynamic) s += " eff=err";
		}
		if (rmPhase != null) {
			try {
				var p:Dynamic = HlxRuntime.callResolved(rmPhase, [sk]);
				if (p != null) s += " ph=" + Std.string(p);
			} catch (_:Dynamic) {}
		}
		if (rmCheckUse != null) {
			var ok:Dynamic = null;
			try ok = HlxRuntime.callResolved(rmCheckUse, [sk]) catch (_:Dynamic) {}
			if (ok == null) try ok = HlxRuntime.callResolved(rmCheckUse, [sk, getHero()]) catch (_:Dynamic) {}
			if (ok == null) try ok = HlxRuntime.callResolved(rmCheckUse, [getHero(), sk]) catch (_:Dynamic) {}
			if (ok != null) s += " use=" + Std.string(ok);
		}
		return s;
	}

	// game says this skill is usable right now despite CD reading (window/charges/flag)
	static function effOf(sk:Dynamic):Dynamic {
		if (sk == null || rmEffSkill == null) return null;
		try {
			var e:Dynamic = HlxRuntime.callResolved(rmEffSkill, [sk]);
			if (e != null && e != sk) return e;
		} catch (_:Dynamic) {}
		return null;
	}

	static function skillFlagUsable(sk:Dynamic):Bool {
		if (sk == null || rmIsIn == null) return false;
		try {
			var b:Dynamic = HlxRuntime.callResolved(rmIsIn, [sk]);
			if (Std.isOfType(b, Bool) && b == false) return true;
		} catch (_:Dynamic) {}
		return false;
	}

	static function usable(sk:Dynamic):Bool {
		if (sk == null) return false;
		if (skillFlagUsable(sk)) return true;
		var ch = chargeInfo(sk);
		if (ch != null && ch.max > 0 && ch.cur > 0) return true;
		// throw-variant: effective skill usable while base is on CD (Void Fangs window)
		var eff = effOf(sk);
		if (eff != null) {
			if (skillFlagUsable(eff)) return true;
			var ec = chargeInfo(eff);
			if (ec != null && ec.max > 0 && ec.cur > 0) return true;
		}
		return false;
	}

	// Game-rule window: raw tryUse bypasses the game's own input validation, so we
	// enforce the rules ourselves — max KNIFE_MAX throws within KNIFE_WINDOW secs
	// of the effective skill appearing (reset on each summon via eff transition).
	static var effActive = new Map<String, Bool>();
	static var effCount = new Map<String, Int>();
	static var effStart = new Map<String, Float>();
	static inline var KNIFE_WINDOW = 8.0;
	static inline var KNIFE_MAX = 3;
	static var lastCastVia = "";

	static function windowOpen(kind:String, sk:Dynamic):Bool {
		var eff = effOf(sk);
		var active = eff != null;
		var was = effActive.get(kind) == true;
		if (active && !was) {
			effCount.set(kind, 0);
			effStart.set(kind, haxe.Timer.stamp());
			trace("window open: " + kind);
		}
		if (!active && was) trace("window closed: " + kind);
		effActive.set(kind, active);
		if (!active) return false;
		var count = effCount.get(kind);
		if (count == null || count >= KNIFE_MAX) return false;
		var start = effStart.get(kind);
		if (start == null) return false;
		return haxe.Timer.stamp() - start <= KNIFE_WINDOW;
	}

	// ground truth for "knives actually out": the BASE skill's effective variant
	// (the _Shoot step's own effOf is always self, so it can't tell)
	static function knivesOut():Bool {
		var base = skillOf("Daggers_Demondash_Skill2");
		if (base == null) return false;
		var eff = effOf(base);
		if (eff == null) return false;
		var ch = chargeInfo(eff);
		if (ch != null && ch.max > 0 && ch.cur <= 0) return false;
		return true;
	}

	static function noteThrow(kind:String):Void {
		var c = effCount.get(kind);
		effCount.set(kind, (c == null ? 0 : c) + 1);
	}

	static function throwsLeft(kind:String):Int {
		var c = effCount.get(kind);
		return KNIFE_MAX - (c == null ? 0 : c);
	}

	// " xN" suffix: remaining throws in the eff window, else own charges
	static function chargeSuffix(kind:String, sk:Dynamic, cd:Float):String {
		if (effOf(sk) != null && windowOpen(kind, sk)) {
			var left = throwsLeft(kind);
			if (left > 0) return " x" + Std.string(left);
		}
		if (cd == -2 || cd <= 0.001) return "";
		var ch = chargeInfo(sk);
		if (ch != null && ch.cur > 0) return " x" + Std.string(ch.cur);
		return "";
	}

	static function isReady(kind:String):Bool {
		var cd = cooldownOf(kind);
		var sk = skillOf(kind);
		// knives out (eff variant visible): window rule is the ONLY gate —
		// base CD reads 0 during the window, so the cd path must not allow it
		if (sk != null && effOf(sk) != null) return knivesOut() && windowOpen(kind, sk);
		if (cd == -2 || (cd >= 0 && cd <= 0.001)) return true;
		if (sk == null) return false;
		var ch = chargeInfo(sk);
		if (ch != null && ch.max > 0 && ch.cur > 0) return true;
		return false;
	}

	// ---------------------------------------------------------------- casting

	static function callTargetFactory(unit:Dynamic):Dynamic {
		if (skillTargetFactory == null) return null;
		try {
			var f:Dynamic = skillTargetFactory;
			return f(unit);
		} catch (_:Dynamic) return null;
	}

	static function findTargetEntity():Dynamic {
		var hero = getHero();
		var ctrl = getController();
		for (src in [hero, ctrl]) {
			if (src == null) continue;
			for (f in ["target", "targetEnemy", "currentTarget", "lockTarget", "aimTarget", "targetUnit"]) {
				try {
					var v:Dynamic = Reflect.field(src, f);
					if (v != null) return v;
				} catch (_:Dynamic) {}
			}
		}
		return null;
	}

	static function buildAimPoint(hero:Dynamic, d:Float):Dynamic {
		var aim:Dynamic = null;
		var pos:Dynamic = null;
		try {
			var m = HlxRuntime.resolveMemberOf(Type.getClass(hero), "getAim3D");
			if (m != null) aim = HlxRuntime.callResolved(m, [hero]);
		} catch (_:Dynamic) {}
		try pos = Reflect.field(hero, "position") catch (_:Dynamic) {}
		if (aim == null || pos == null) return null;
		var vec:Dynamic = null;
		try {
			var mc = HlxRuntime.resolveMemberOf(Type.getClass(aim), "clone");
			if (mc != null) vec = HlxRuntime.callResolved(mc, [aim]);
		} catch (_:Dynamic) {}
		if (vec == null) return null;
		try {
			var ax:Float = Reflect.field(aim, "x");
			var ay:Float = Reflect.field(aim, "y");
			var az:Float = Reflect.field(aim, "z");
			var px:Float = Reflect.field(pos, "x");
			var py:Float = Reflect.field(pos, "y");
			var pz:Float = Reflect.field(pos, "z");
			Reflect.setField(vec, "x", px + ax * d);
			Reflect.setField(vec, "y", py + ay * d);
			Reflect.setField(vec, "z", pz + az * d);
		} catch (_:Dynamic) return null;
		return vec;
	}

	static var tgtProbed = false;

	static function isUnitClass(cn:String):Bool {
		return cn.indexOf("ent.") == 0 || cn.indexOf("Foe") >= 0 || cn.indexOf("Hero") >= 0
			|| cn.indexOf("Unit") >= 0 || cn.indexOf("GameObject") >= 0;
	}

	static function findUnitTarget():Dynamic {
		var hero = getHero();
		var ctrl = getController();
		if (hero == null) return null;
		var unit:Dynamic = null;
		for (i in 0...2) {
			var src:Dynamic = i == 0 ? hero : ctrl;
			if (src == null) continue;
			var tag = i == 0 ? "hero" : "ctrl";
			for (f in ["target", "targetEnemy", "currentTarget", "lockTarget", "aimTarget", "targetUnit", "lockedTarget", "autoTarget"]) {
				try {
					var v:Dynamic = Reflect.field(src, f);
					if (v == null) continue;
					var cc = Type.getClass(v);
					var cn = cc != null ? Std.string(Type.getClassName(cc)) : "prim:" + Std.string(v);
					if (!tgtProbed) trace("tgtprobe: " + tag + "." + f + " class=" + cn);
					if (cc != null && isUnitClass(cn) && unit == null) unit = v;
				} catch (_:Dynamic) {}
			}
		}
		if (unit == null && ctrl != null) {
			for (m in ["getTarget", "getLockedTarget", "getLockTarget", "getAimTarget", "getAutoTarget"]) {
				try {
					var rm = HlxRuntime.resolveMemberOf(Type.getClass(ctrl), m);
					if (rm == null) continue;
					var v:Dynamic = HlxRuntime.callResolved(rm, [ctrl]);
					var cc = v != null ? Type.getClass(v) : null;
					var cn = cc != null ? Std.string(Type.getClassName(cc)) : "null";
					if (!tgtProbed) trace("tgtprobe: ctrl." + m + "() class=" + cn);
					if (cc != null && isUnitClass(cn)) {
						unit = v;
						break;
					}
				} catch (e:Dynamic) {
					if (!tgtProbed) trace("tgtprobe: ctrl." + m + " err " + e);
				}
			}
		}
		if (!tgtProbed && unit == null) trace("tgtprobe: no unit found");
		return unit;
	}

	// throw target: prefer Target(unit) (guided homing like the game's own input),
	// fall back to aim-ray points. Only checkUse "Ok" is accepted.
	static function findThrowTarget(sk:Dynamic, eff:Dynamic):Dynamic {
		if (rmCheckUse == null) return null;
		var tTarget = HlxRuntime.resolveType("st.skill.SkillTarget");
		if (tTarget == null) return null;
		var hero = getHero();
		if (hero == null) return null;
		var chkSkill:Dynamic = eff != null ? eff : sk;
		var unit = findUnitTarget();
		if (unit != null && skillTargetFactory != null) {
			var tv:Dynamic = callTargetFactory(unit);
			if (tv != null) {
				try {
					var cs = Std.string(HlxRuntime.callResolved(rmCheckUse, [chkSkill, tv]));
					trace("throw: checkUse unit -> " + cs);
					if (cs == "Ok") return tv;
				} catch (e:Dynamic) {
					trace("throw: checkUse unit err " + e);
				}
			}
		}
		for (d in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0]) {
			var vec = buildAimPoint(hero, d);
			if (vec == null) {
				trace("throw: aim point build failed");
				return null;
			}
			var pt:Dynamic = null;
			try {
				pt = HlxRuntime.constructEnum(tTarget, "Point", [vec]);
			} catch (e:Dynamic) {
				trace("throw: Point err " + e);
				return null;
			}
			if (pt == null) continue;
			for (chk in [eff, sk]) {
				if (chk == null) continue;
				try {
					var cs = Std.string(HlxRuntime.callResolved(rmCheckUse, [chk, pt]));
					if (!tgtProbed) trace("throw: checkUse " + (chk == eff ? "eff" : "base") + " d=" + d + " -> " + cs);
					if (cs == "Ok") {
						tgtProbed = true;
						return pt;
					}
				} catch (e:Dynamic) {
					trace("throw: checkUse d=" + d + " err " + e);
				}
			}
		}
		tgtProbed = true;
		trace("throw: no Ok target (unit=" + (unit != null) + ")");
		return null;
	}

	static function tryCast(kind:String):Bool {
		if (!ensureResolved()) return false;
		var hero = getHero();
		if (hero == null) return false;
		var sk = skillOf(kind);
		if (sk == null) {
			trace("skill not found: " + kind);
			return false;
		}
		var eff = effOf(sk);
		var inWindow = eff != null && windowOpen(kind, sk);
		var isShootKind = kind.indexOf("_Shoot") >= 0;
		var tgt:Dynamic = null;
		var cands:Array<Dynamic>;
		var labels:Array<String>;
		if (inWindow || isShootKind) {
			if (!knivesOut()) {
				trace("throw: no knives out - skip");
				return false;
			}
			// throw path: target required (game's input attaches the locked foe -> homing)
			var useSkill:Dynamic = eff != null ? eff : sk;
			tgt = findThrowTarget(sk, useSkill);
			if (tgt == null) {
				trace("throw: no valid target - skip (no blind shot)");
				return false;
			}
			cands = [useSkill];
			labels = ["eff"];
		} else {
			tgt = null;
			cands = [sk];
			labels = ["base"];
		}
		var ctrl = getController();
		var lastErr:String = null;
		for (ci in 0...cands.length) {
			var s = cands[ci];
			if (ctrl != null && rmTryUse != null) {
				try {
					var r:Dynamic = HlxRuntime.callResolved(rmTryUse, [ctrl, s, tgt]);
					if (!Std.isOfType(r, Bool) || r == true) { lastCastVia = labels[ci]; noteActivity(); return true; }
					lastErr = "rejected";
				} catch (e:Dynamic) lastErr = Std.string(e);
			}
			if (rmDoUse != null) {
				try {
					var r:Dynamic = HlxRuntime.callResolved(rmDoUse, [hero, s, tgt, null]);
					if (!Std.isOfType(r, Bool) || r == true) { lastCastVia = labels[ci]; noteActivity(); return true; }
					lastErr = "rejected";
				} catch (e:Dynamic) lastErr = Std.string(e);
			}
		}
		if (lastErr != null) trace("cast failed " + kind + ": " + lastErr);
		return false;
	}

	// ---------------------------------------------------------------- chaos mark gate

	static function statusName(st:Dynamic):String {
		for (f in ["kind", "name", "statusName", "id"]) {
			try {
				var v:Dynamic = Reflect.field(st, f);
				if (v != null) {
					var s = Std.string(v);
					if (s != "" && s != "unknown" && s != "st.skill.Status") return s;
				}
			} catch (_:Dynamic) {}
		}
		try {
			var cc = Type.getClass(st);
			if (cc != null) {
				var cn = Std.string(Type.getClassName(cc));
				if (cn != null && cn != "" && cn != "unknown" && cn != "st.skill.Status") return cn;
			}
		} catch (_:Dynamic) {}
		var str = Std.string(st);
		var h = str.indexOf("#");
		return h > 0 ? str.substring(0, h) : str;
	}

	static function isMarkName(s:String):Bool {
		for (m in MARK_STATUSES) if (s == m) return true;
		return s.toLowerCase().indexOf("chaos") >= 0;
	}

	static function getMarkTarget():Dynamic {
		var t = findUnitTarget();
		if (t != null) return t;
		var hero = getHero();
		if (hero == null) return null;
		for (m in ["get_target", "get_targetUnit", "getTarget"]) {
			try {
				var rm = HlxRuntime.resolveMemberOf(Type.getClass(hero), m);
				if (rm == null) continue;
				var v:Dynamic = HlxRuntime.callResolved(rm, [hero]);
				if (v != null) return v;
			} catch (_:Dynamic) {}
		}
		return null;
	}

	static function targetHasChaosMark():Bool {
		var target = getMarkTarget();
		if (target == null) return false;
		try {
			var statuses:Dynamic = Reflect.field(target, "statuses");
			if (statuses == null) return false;
			var arr:Dynamic = statuses;
			var pa = Reflect.field(arr, "array");
			if (pa != null) {
				var da = Reflect.field(pa, "array");
				if (da != null) arr = da;
			}
			var getDyn = Reflect.field(arr, "getDyn");
			if (getDyn != null) {
				for (i in 0...100) {
					var st:Dynamic = null;
					try st = Reflect.callMethod(arr, getDyn, [i]) catch (_:Dynamic) {}
					if (st == null) break;
					if (isMarkName(statusName(st))) return true;
				}
			}
		} catch (_:Dynamic) {}
		return false;
	}

	// extra cast permission per step; null = allowed
	static function gateReason(kind:String):String {
		if (kind == PLUNGE_KIND && plungeGateOn() && !targetHasChaosMark())
			return "target has no Chaos Mark";
		return null;
	}

	// ---------------------------------------------------------------- combat state

	static var combatPathLogged = false;
	static var combatWas = false;
	static var lastActivityAt:Float = -999;
	static var lastHeroHp:Float = -1;
	static var lastTgtHp:Float = -1;

	static function noteActivity():Void {
		lastActivityAt = haxe.Timer.stamp();
	}

	// game truth first: unit.isInCombat is used by the shipped skill scripts
	// (skills_only.json); null when the property can't be read -> activity fallback
	static function combatFlag():Null<Bool> {
		var hero = getHero();
		if (hero == null) return null;
		for (f in ["isInCombat", "inCombat"]) {
			try {
				var v:Dynamic = Reflect.field(hero, f);
				if (v == null) {
					var g:Dynamic = Reflect.field(hero, "get_" + f);
					if (g != null && Reflect.isFunction(g)) v = Reflect.callMethod(hero, g, []);
				}
				if (Std.isOfType(v, Bool)) {
					if (!combatPathLogged) { combatPathLogged = true; trace("combat: using hero." + f); }
					return cast v;
				}
				if (v != null && Reflect.isFunction(v)) {
					var r:Dynamic = Reflect.callMethod(hero, v, []);
					if (Std.isOfType(r, Bool)) {
						if (!combatPathLogged) { combatPathLogged = true; trace("combat: using hero." + f + "()"); }
						return cast r;
					}
				}
			} catch (_:Dynamic) {}
		}
		return null;
	}

	static function readHp(o:Dynamic):Float {
		for (f in ["hp", "health", "life"]) {
			try {
				var v:Dynamic = Reflect.field(o, f);
				if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return cast v;
			} catch (_:Dynamic) {}
		}
		return -1;
	}

	// fallback when the game flag can't be read: recent casts or hp DROPS
	// count as activity (regen/raises are ignored so out-of-combat heals
	// don't keep the fight "alive")
	static function pollActivity():Void {
		var now = haxe.Timer.stamp();
		var hero = getHero();
		if (hero == null) return;
		var hp = readHp(hero);
		if (hp >= 0) {
			if (lastHeroHp >= 0 && hp < lastHeroHp) lastActivityAt = now;
			lastHeroHp = hp;
		}
		var t = getMarkTarget();
		if (t != null) {
			var thp = readHp(t);
			if (thp >= 0) {
				if (lastTgtHp >= 0 && thp < lastTgtHp) lastActivityAt = now;
				lastTgtHp = thp;
			}
		} else lastTgtHp = -1;
	}

	// what advanceAndCast would actually cast right now (priority pass first)
	static function nextCastIdx():Int {
		var len = config.steps.length;
		if (len == 0) return -1;
		var c = cursor >= len ? 0 : cursor;
		var walkLen = strictOn() ? 1 : len;
		for (n in 0...walkLen) {
			var idx = (c + n) % len;
			var kind = config.steps[idx];
			if (gateReason(kind) != null) continue;
			var sk = skillOf(kind);
			if (sk != null && effOf(sk) != null && knivesOut() && windowOpen(kind, sk)) return idx;
		}
		for (n in 0...walkLen) {
			var idx = (c + n) % len;
			var kind = config.steps[idx];
			if (gateReason(kind) != null) continue;
			if (isReady(kind)) return idx;
		}
		return -1;
	}

	// Priority walk: from cursor forward (wrapping) cast the first ready step.
	// After a cast on the last step, cursor wraps to 0 (full loop reset).
	static function advanceAndCast():Void {
		var len = config.steps.length;
		if (len == 0) return;
		dumpSlots("trigger");
		if (cursor >= len) cursor = 0;
		// strict order: try ONLY the cursor step — mashing the trigger can
		// never skip a not-ready/rejected step or wrap out of sequence
		var walkLen = strictOn() ? 1 : len;
		// charge-window skills (Void Fangs knives) jump the queue while charges last:
		// CD says not-ready, but charges keep it throwable until the window expires
		for (n in 0...walkLen) {
			var idx = (cursor + n) % len;
			var kind = config.steps[idx];
			if (gateReason(kind) != null) continue;
			var skP = skillOf(kind);
			if (skP != null && effOf(skP) != null && windowOpen(kind, skP)) {
				if (tryCast(kind)) {
					noteThrow(kind);
					trace("cast(charged) " + kind + " at " + idx + " via=" + lastCastVia + " left=" + throwsLeft(kind));
					cursor = (idx + 1) % len;
					return;
				}
				// real window but cast failed: don't spam other steps either
				if (knivesOut()) return;
				// bogus window (e.g. _Shoot step's always-self effOf, no knives): fall through
			}
		}
		for (n in 0...walkLen) {
			var idx = (cursor + n) % len;
			var kind = config.steps[idx];
			if (gateReason(kind) != null) continue;
			if (isReady(kind)) {
				if (tryCast(kind)) {
					trace("cast " + kind + " at " + idx);
					cursor = (idx + 1) % len;
					var csk = skillOf(kind);
					var pcd = "?";
					if (csk != null && rmCdLeft != null) {
						try {
							var pv:Dynamic = HlxRuntime.callResolved(rmCdLeft, [csk]);
							pcd = Std.string(pv);
						} catch (_:Dynamic) pcd = "err";
					}
					trace("postcast " + kind + " cd=" + pcd + diagOf(csk));
					return;
				}
				// ready-looking step that can't actually cast (e.g. _Shoot with no
				// knives): keep walking so other ready steps still fire this press
			}
		}
		if (strictOn()) {
			var k = config.steps[cursor];
			var gr = gateReason(k);
			if (gr != null) {
				trace("strict: hold step " + (cursor + 1) + "/" + len + " " + k + " - " + gr);
				return;
			}
			var cd = cooldownOf(k);
			var cdS = cd == -1 ? "not found" : cd == -2 ? "cd unknown" : Std.string(Math.round(cd * 10) / 10) + "s";
			trace("strict: hold step " + (cursor + 1) + "/" + len + " " + k + " cd=" + cdS + (isReady(k) ? " ready but rejected" : ""));
			return;
		}
		var sum = [];
		for (kind in config.steps) {
			var cd = cooldownOf(kind);
			sum.push(kind + "=" + (cd == -1 ? "nf" : cd == -2 ? "unk" : Std.string(Math.round(cd * 10) / 10)) + diagOf(skillOf(kind)));
		}
		trace("trigger: no skill ready; " + sum.join(" "));
	}

	// ---------------------------------------------------------------- probe (dev)

	static function probe():Void {
		if (probed) return;
		if (!ensureResolved()) return;
		var hero = getHero();
		if (hero == null) return;
		probed = true;

		var ctrl = getController();
		trace("probe: controller=" + (ctrl != null) + " hero=" + (hero != null));

		for (f in ["attackSkills", "weaponSkills", "skillSlots", "secondarySkill", "dashSkill", "attackComboSkill"]) {
			try {
				var arr:Dynamic = Reflect.field(hero, f);
				if (arr == null) {
					trace("probe " + f + " = null");
				} else {
					var a:Dynamic = arr;
					var proxy = Reflect.field(a, "array");
					if (proxy != null) {
						var dynArr = Reflect.field(proxy, "array");
						if (dynArr != null) a = dynArr;
					}
					var getDyn = Reflect.field(a, "getDyn");
					var n = 0;
					if (getDyn != null) {
						for (i in 0...30) {
							var sk:Dynamic = null;
							try sk = Reflect.callMethod(a, getDyn, [i]) catch (_:Dynamic) {}
							if (sk == null) break;
						var kind = fieldStr(sk, "kind");
						if (kind == null && Std.isOfType(sk, String)) kind = cast sk;
						if (kind == null) kind = fieldStr(sk, "skillId");
							if (kind == null) kind = fieldStr(sk, "id");
							if (kind == null) kind = fieldStr(sk, "name");
							var cls = "?";
							try cls = Type.getClassName(Type.getClass(sk)) catch (_:Dynamic) {}
							trace("probe " + f + "[" + i + "] kind=" + kind + " cls=" + cls);
							if (i == 0) {
								try {
									var flds = Type.getInstanceFields(Type.getClass(sk));
									trace("probe fields: " + flds.join(","));
								} catch (_:Dynamic) {}
							}
							n++;
						}
					}
					trace("probe " + f + " count=" + n);
				}
			} catch (e:Dynamic) {
				trace("probe " + f + " error: " + e);
			}
		}
	}

	static function fieldStr(o:Dynamic, name:String):String {
		var v:Dynamic = Reflect.field(o, name);
		if (v == null) return null;
		var s = Std.string(v);
		return (s == "" || s == "null") ? null : s;
	}

	// ---------------------------------------------------------------- UI

	static function ensureImGui():Void {
		if (imguiRegistered || imguiInitAttempted) return;
		imguiInitAttempted = true;
		try {
			ImGui.register(HlxRuntime.moduleName(), draw);
			imguiRegistered = true;
		} catch (_:Dynamic) {
			imguiRegistered = false;
		}
	}

	static function currentStep():String {
		if (config.steps.length == 0) return null;
		if (cursor >= config.steps.length) cursor = 0;
		return config.steps[cursor];
	}

	// ---------------------------------------------------------------- shoot api dump (dev)

	static var shootDumped = false;

	static function dumpFieldsChunked(tag:String, c:Class<Dynamic>):Void {
		try {
			var fs = Type.getInstanceFields(c);
			if (fs == null || fs.length == 0) return;
			var all = fs.join(",");
			var pos = 0;
			var chunk = 0;
			while (pos < all.length) {
				var n = all.length - pos > 900 ? 900 : all.length - pos;
				trace("dump: " + tag + " fields[" + chunk + "]: " + all.substr(pos, n));
				pos += n;
				chunk++;
			}
		} catch (e:Dynamic) {
			trace("dump " + tag + " fields err: " + e);
		}
	}

	static function dumpShootApi():Void {
		if (shootDumped || isHotkeyMode()) return;
		var sk = skillOf("Daggers_Demondash_Skill2");
		if (sk == null) return;
		var eff = effOf(sk);
		if (eff == null) return;
		shootDumped = true;
		try {
			dumpShootApiInner(sk, eff);
		} catch (e:Dynamic) {
			trace("dump: error " + e);
			trace("dump stack: " + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
		}
	}

	static function dumpScriptFor(tag:String, s:Dynamic, names:Array<String>):Void {
		try {
			var sc:Dynamic = Reflect.field(s, "script");
			if (sc == null) {
				trace("dump: " + tag + " script=null");
				return;
			}
			var c = Type.getClass(sc);
			trace("dump: " + tag + " script class=" + (c != null ? Type.getClassName(c) : "null"));
			if (c != null) dumpFieldsChunked(tag + " script", c);
			for (nm in names) {
				try {
					var m = HlxRuntime.resolveMemberOf(c, nm);
					if (m == null) continue;
					try {
						var r:Dynamic = HlxRuntime.callResolved(m, [sc]);
						trace("dump: " + tag + "." + nm + "() executed ret=" + Std.string(r));
					} catch (eC:Dynamic) {
						trace("dump: " + tag + "." + nm + " err: " + eC);
					}
				} catch (e:Dynamic) {}
			}
		} catch (e:Dynamic) {
			trace("dump: " + tag + " script err: " + e);
		}
	}

	static function tryPoint(tag:String, tTarget:Dynamic, arg:Dynamic, cands:Array<Dynamic>, cnames:Array<String>):Void {
		if (arg == null) return;
		try {
			var p:Dynamic = HlxRuntime.constructEnum(tTarget, "Point", [arg]);
			if (p != null) {
				cands.push(p);
				cnames.push("Point(" + tag + ")");
				trace("dump: Point(" + tag + ") built");
			} else {
				trace("dump: Point(" + tag + ") = null");
			}
		} catch (e:Dynamic) {
			trace("dump: Point(" + tag + ") err: " + e);
		}
	}

	static function dumpShootApiInner(sk:Dynamic, eff:Dynamic):Void {
		trace("dump: ==== Void Fangs v5 (fireProjectile + 1-arg target) ====");
		dumpScriptFor("base", sk, ["makeTarget"]);
		dumpScriptFor("eff", eff, ["fireProjectile", "onUseSkill", "makeTarget"]);

		var tTarget = HlxRuntime.resolveType("st.skill.SkillTarget");
		trace("dump: tTarget resolved=" + (tTarget != null));
		var cands = new Array<Dynamic>();
		var cnames = new Array<String>();
		var hero = getHero();
		if (hero == null) {
			trace("dump: no hero");
			return;
		}
		var aim:Dynamic = null;
		try {
			var rmAim = HlxRuntime.resolveMemberOf(Type.getClass(hero), "getAim3D");
			aim = rmAim != null ? HlxRuntime.callResolved(rmAim, [hero]) : null;
			var an = aim != null ? Std.string(Type.getClassName(Type.getClass(aim))) : "null";
			var av = "n/a";
			if (aim != null) {
				try av = "(" + Std.string(Reflect.field(aim, "x")) + "," + Std.string(Reflect.field(aim, "y")) + "," + Std.string(Reflect.field(aim, "z")) + ")" catch (_:Dynamic) {}
			}
			trace("dump: aim class=" + an + " " + av);
		} catch (e:Dynamic) {
			trace("dump: aim err " + e);
		}
		var posObj:Dynamic = null;
		for (f in ["pos", "position", "worldPos"]) {
			try {
				var p:Dynamic = Reflect.field(hero, f);
				if (p != null) {
					trace("dump: hero." + f + " class=" + Std.string(Type.getClassName(Type.getClass(p))));
					if (posObj == null) posObj = p;
				}
			} catch (e:Dynamic) {}
		}
		for (mn in ["getPos", "getPosition", "getPos3D", "getWorldPos"]) {
			if (posObj != null) break;
			try {
				var m = HlxRuntime.resolveMemberOf(Type.getClass(hero), mn);
				if (m == null) continue;
				var p:Dynamic = HlxRuntime.callResolved(m, [hero]);
				if (p != null) {
					trace("dump: hero." + mn + " -> class=" + Std.string(Type.getClassName(Type.getClass(p))));
					posObj = p;
				}
			} catch (e:Dynamic) {
				trace("dump: hero." + mn + " err: " + e);
			}
		}
		var foe:Dynamic = null;
		try {
			var esc:Dynamic = Reflect.field(eff, "script");
			var ec = esc != null ? Type.getClass(esc) : null;
			if (ec != null) {
				for (nm in ["findTarget", "getBestTarget", "getAITarget"]) {
					if (foe != null) break;
					try {
						var m = HlxRuntime.resolveMemberOf(ec, nm);
						if (m == null) continue;
						var r:Dynamic = HlxRuntime.callResolved(m, [esc]);
						var rn = r != null ? Std.string(Type.getClassName(Type.getClass(r))) : "null";
						trace("dump: foe via " + nm + " -> class=" + rn);
						if (r != null && rn.indexOf("GameObject") >= 0) foe = r;
					} catch (e:Dynamic) {
						trace("dump: foe via " + nm + " err: " + e);
					}
				}
			}
		} catch (e:Dynamic) {
			trace("dump: foe block err " + e);
		}
		if (tTarget != null) {
			var arr3 = [Reflect.field(aim, "x"), Reflect.field(aim, "y"), Reflect.field(aim, "z")];
			tryPoint("aim", tTarget, aim, cands, cnames);
			tryPoint("aimArr", tTarget, arr3, cands, cnames);
			tryPoint("pos", tTarget, posObj, cands, cnames);
			if (foe != null) {
				try {
					var t:Dynamic = HlxRuntime.constructEnum(tTarget, "Target", [foe]);
					if (t != null) {
						cands.push(t);
						cnames.push("Target(foe)");
						trace("dump: Target(foe) built");
					}
				} catch (e:Dynamic) {
					trace("dump: Target(foe) err: " + e);
				}
			}
		}
		if (rmCheckUse != null) {
			if (cands.length == 0) trace("dump: no target candidates built");
			for (i in 0...cands.length) {
				try {
					var r1:Dynamic = HlxRuntime.callResolved(rmCheckUse, [eff, cands[i]]);
					trace("dump: checkUse eff @ " + cnames[i] + " = " + Std.string(r1));
				} catch (e:Dynamic) {
					trace("dump: checkUse eff @ " + cnames[i] + " err: " + e);
				}
				try {
					var r0:Dynamic = HlxRuntime.callResolved(rmCheckUse, [sk, cands[i]]);
					trace("dump: checkUse base @ " + cnames[i] + " = " + Std.string(r0));
				} catch (e:Dynamic) {
					trace("dump: checkUse base @ " + cnames[i] + " err: " + e);
				}
			}
		}
	}

	static function draw():Void {
		drawHud();
		if (config.editorOpen) drawEditor();
	}

	static var drawHudErrLogged = 0;

	static function drawHud():Void {
		var opened = false;
		try {
			ImGui.setNextWindowBgAlpha(0.7);
			opened = ImGui.begin("##cshud", null,
				ImGuiWindowFlags.NoTitleBar | ImGuiWindowFlags.NoResize | ImGuiWindowFlags.NoMove | ImGuiWindowFlags.AlwaysAutoResize);
			if (isHotkeyMode()) {
				var keys = hotkeyList();
				if (keys.length == 0) {
					ImGui.textDisabled("Cast Sequence: empty hotkey sequence (open editor)");
				} else {
					if (cursor >= keys.length) cursor = 0;
					ImGui.pushStyleColor(ImGuiCol.Text, 0xFF00FF00);
					ImGui.button(keys[cursor]);
					ImGui.popStyleColor();
					ImGui.sameLine();
					ImGui.textDisabled("(" + (cursor + 1) + "/" + keys.length + ")");
				}
				ImGui.sameLine();
				if (ImGui.smallButton("Edit")) {
					config.editorOpen = !config.editorOpen;
					config.save();
				}
			} else {
			var nidx = nextCastIdx();
			var step = nidx >= 0 ? config.steps[nidx] : currentStep();
			if (step == null) {
				ImGui.textDisabled("Cast Sequence: empty (open editor)");
			} else {
				var cd = cooldownOf(step);
				var skS = skillOf(step);
				var ready = isReady(step);
				var col = 0xFFFFFFFF;
				var status = "";
				if (cd == -1) { col = 0xFF4444FF; status = "NOT FOUND"; }
				else if (ready) {
					col = 0xFF00FF00;
					status = "READY" + chargeSuffix(step, skS, cd);
				}
				else { col = 0xFF00A5FF; status = (Math.round(cd * 10) / 10) + "s" + chargeSuffix(step, skS, cd); }

				ImGui.pushStyleColor(ImGuiCol.Text, col);
				ImGui.button(step);
				ImGui.popStyleColor();
				ImGui.sameLine();
				ImGui.pushStyleColor(ImGuiCol.Text, col);
				ImGui.text(status);
				ImGui.popStyleColor();

				if (config.steps.length > 1) {
					ImGui.sameLine();
					ImGui.textDisabled("(" + (nidx >= 0 ? nidx + 1 : cursor + 1) + "/" + config.steps.length + ")");
				}
				ImGui.sameLine();
				if (ImGui.smallButton("Edit")) {
					config.editorOpen = !config.editorOpen;
					config.save();
				}
			}
			}
		} catch (e:Dynamic) {
			if (drawHudErrLogged < 3) {
				drawHudErrLogged++;
				trace("drawHud error: " + e);
			}
			imguiRegistered = false;
		}
		if (opened) {
			try ImGui.end() catch (_:Dynamic) {}
		}
	}

	static var drawEdErrLogged = 0;

	static function drawEditor():Void {
		var opened = false;
		try {
			var visible = ImGui.begin("Cast Sequence", null, ImGuiWindowFlags.AlwaysAutoResize);
			opened = true;
			if (visible) {
			var en = new BoolRef(config.enabled);
			if (ImGui.checkbox("Enabled", en)) {
				config.enabled = en.get();
				config.save();
			}
			ImGui.sameLine();
			ImGui.textDisabled(isHotkeyMode() ? "trigger = press next key in sequence" : "trigger = cast the skill shown in the HUD slot");

			var idx = KEY_VALUES.indexOf(config.triggerKey);
			if (idx < 0) idx = 0;
			if (ImGui.beginCombo("Trigger key", KEY_NAMES[idx])) {
				for (i in 0...KEY_NAMES.length) {
					if (ImGui.selectable(KEY_NAMES[i], i == idx)) {
						config.triggerKey = KEY_VALUES[i];
						idx = i;
						config.save();
					}
				}
				ImGui.endCombo();
			}

			ImGui.separator();
			var hkMode = isHotkeyMode();
			if (ImGui.button(hkMode ? "Mode: Hotkeys" : "Mode: Skills")) {
				config.mode = hkMode ? "skill" : "hotkey";
				config.save();
			}
			ImGui.sameLine();
			ImGui.textDisabled(hkMode ? "trigger = press next key / mouse button in sequence" : (strictOn() ? "trigger = cast the current step (strict order)" : "trigger = cast the next ready skill"));

			if (hkMode) {
				ImGui.text("Sequence (keys separated by >):");
				if (ImGui.inputText("##hotkeys", hkBuf, HK_BUF_SIZE, ImGuiInputTextFlags.None)) {
					var s = @:privateAccess String.fromUTF8(hkBuf);
					config.hotkeys = StringTools.trim(s);
					hkCacheSrc = null;
					config.save();
				}
				ImGui.textDisabled("A-Z / 0-9 = keys; T or MB1 = mouse back; MB2 = mouse forward");
				var dref = new IntRef(stepDelayMsOrDefault());
				if (ImGui.inputInt("Step delay ms", dref)) {
					config.stepDelayMs = dref.get();
					config.save();
				}
				var keys = hotkeyList();
				if (keys.length == 0) ImGui.textDisabled("(empty)");
				for (i in 0...keys.length) {
					ImGui.pushID_Str("hk" + i);
					if (i == cursor) {
						ImGui.pushStyleColor(ImGuiCol.Text, 0xFF00FF00);
						ImGui.text(">");
						ImGui.popStyleColor();
					} else {
						ImGui.text(" ");
					}
					ImGui.sameLine();
					var ok = classify(keys[i]) != null;
					ImGui.pushStyleColor(ImGuiCol.Text, ok ? 0xFF00FF00 : 0xFF4444FF);
					ImGui.text(keys[i]);
					ImGui.popStyleColor();
					if (!ok) {
						ImGui.sameLine();
						ImGui.textDisabled("invalid");
					}
					ImGui.popID();
				}
			} else {
			var so = new BoolRef(strictOn());
			if (ImGui.checkbox("Strict order", so)) {
				config.strictOrder = so.get();
				config.save();
			}
			ImGui.sameLine();
			ImGui.textDisabled("each press = current step only, never skips ahead");

			var pm = new BoolRef(plungeGateOn());
			if (ImGui.checkbox("Plunge needs Chaos Mark", pm)) {
				config.plungeNeedsMark = pm.get();
				config.save();
			}
			ImGui.sameLine();
			ImGui.textDisabled("hold Infernal Plunge until the target is marked");

			ImGui.text(strictOn() ? "Sequence (order enforced):" : "Sequence (priority order):");

			var removeIdx = -1;
			for (i in 0...config.steps.length) {
				var kind = config.steps[i];
				ImGui.pushID_Str("step" + i);
				if (i == cursor) {
					ImGui.pushStyleColor(ImGuiCol.Text, 0xFF00FF00);
					ImGui.text(">");
					ImGui.popStyleColor();
				} else {
					ImGui.text(" ");
				}
				ImGui.sameLine();

				var cd = cooldownOf(kind);
				var skE = skillOf(kind);
				var ready = isReady(kind);
				if (cd == -1) ImGui.pushStyleColor(ImGuiCol.Text, 0xFF4444FF);
				else if (ready) ImGui.pushStyleColor(ImGuiCol.Text, 0xFF00FF00);
				else ImGui.pushStyleColor(ImGuiCol.Text, 0xFF00A5FF);
				ImGui.text(kind);
				ImGui.popStyleColor();
				ImGui.sameLine();
				if (cd == -1) ImGui.textDisabled("not found");
				else if (ready)
					ImGui.textDisabled("ready" + chargeSuffix(kind, skE, cd));
				else ImGui.textDisabled((Math.round(cd * 10) / 10) + "s" + chargeSuffix(kind, skE, cd));

				ImGui.sameLine();
				if (i > 0 && ImGui.smallButton("^")) moveStep(i, i - 1);
				ImGui.sameLine();
				if (i < config.steps.length - 1 && ImGui.smallButton("v")) moveStep(i, i + 1);
				ImGui.sameLine();
				if (ImGui.smallButton("X")) removeIdx = i;

				ImGui.popID();
				if (removeIdx >= 0) break;
			}
			if (removeIdx >= 0) deleteStep(removeIdx);

			ImGui.separator();
			var submitted = ImGui.inputText("##addstep", addBuf, ADD_BUF_SIZE, ImGuiInputTextFlags.EnterReturnsTrue);
			ImGui.sameLine();
			var clicked = ImGui.button("Add");
			if (submitted || clicked) {
				var s = @:privateAccess String.fromUTF8(addBuf);
				s = StringTools.trim(s);
				if (s != "") {
					config.steps.push(s);
					config.save();
				}
				fillBuf(addBuf, ADD_BUF_SIZE, "");
			}
			ImGui.sameLine();
			ImGui.textDisabled("skill kind, e.g. Daggers_Demondash_Skill1");
			}

			if (ImGui.button("Reset cursor")) cursor = 0;
			ImGui.sameLine();
			if (ImGui.button("Close")) {
				config.editorOpen = false;
				config.save();
			}
		}
		} catch (e:Dynamic) {
			if (drawEdErrLogged < 3) {
				drawEdErrLogged++;
				trace("drawEditor error: " + e);
			}
		}
		if (opened) {
			try ImGui.end() catch (_:Dynamic) {}
		}
	}

	// ---------------------------------------------------------------- list ops

	static function moveStep(from:Int, to:Int):Void {
		var s = config.steps;
		var tmp = s[from];
		s[from] = s[to];
		s[to] = tmp;
		if (cursor == from) cursor = to;
		else if (cursor == to) cursor = from;
		config.save();
	}

	static function deleteStep(i:Int):Void {
		config.steps.splice(i, 1);
		if (cursor > i) cursor--;
		else if (cursor == i && cursor >= config.steps.length) cursor = 0;
		config.save();
	}

	static function fillBuf(buf:hl.Bytes, size:Int, s:String):Void {
		var utf8 = @:privateAccess s.toUtf8();
		var len = 0;
		while (len < size - 1 && utf8.getUI8(len) != 0)
			len++;
		buf.blit(0, utf8, 0, len);
		buf.setUI8(len, 0);
	}

	// ---------------------------------------------------------------- tick

	static var statusLogged = false;
	static var updateErrLogged = 0;

	@:hlx.postfix(GameApp.update)
	static function onGameAppUpdate(instance:Dynamic, dt:Float, result:Void):Void {
		ensureImGui();
		try {
			if (!isHotkeyMode()) probe();
			dumpShootApi();
			// combat end -> back to step 1 (fresh combo for the next fight)
			var flag = combatFlag();
			var cb:Bool;
			if (flag != null) cb = flag;
			else {
				pollActivity();
				cb = haxe.Timer.stamp() - lastActivityAt < 4.0;
			}
			if (combatWas && !cb && cursor != 0) {
				trace("combat end: cursor reset " + cursor + " -> 0");
				cursor = 0;
			}
			combatWas = cb;
			if (!isHotkeyMode() && !statusLogged && probed && config.steps.length > 0) {
				statusLogged = true;
				var seen = new Map<String, Bool>();
				for (kind in config.steps) {
					if (seen.exists(kind)) continue;
					seen.set(kind, true);
					var sk = skillOf(kind);
					var line = "status " + kind + " found=" + (sk != null);
					if (sk != null && rmCdLeft != null) {
						try {
							var v:Dynamic = HlxRuntime.callResolved(rmCdLeft, [sk]);
							line += " cdRaw=" + Std.string(v);
						} catch (e:Dynamic) line += " cdErr=" + e;
					}
					line += diagOf(sk);
					trace(line);
				}
			}
			var trigCount = isHotkeyMode() ? hotkeyList().length : config.steps.length;
			if (trigCount > 0 && ImGui.isKeyPressed(config.triggerKey, false)) {
				if (!config.enabled) {
					trace("trigger key=" + config.triggerKey + " ignored (enabled=false)");
				} else if (isHotkeyMode()) {
					var now = haxe.Timer.stamp();
					var delay = stepDelayMsOrDefault() / 1000.0;
					if (now - lastHotkeyAt < delay) {
						trace("hotkey: step delay active");
					} else {
						var keys = hotkeyList();
						if (cursor >= keys.length) cursor = 0;
						var tok = keys[cursor];
						trace("hotkey " + tok + " at " + cursor + "/" + keys.length);
						pressToken(tok);
						lastHotkeyAt = now;
						cursor = (cursor + 1) % keys.length;
					}
				} else {
					trace("trigger key=" + config.triggerKey + " cursor=" + cursor + "/" + config.steps.length);
					advanceAndCast();
				}
			}
		} catch (e:Dynamic) {
			if (updateErrLogged < 5) {
				updateErrLogged++;
				trace("update error (attempt " + updateErrLogged + "): " + e);
				trace("update stack: " + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
			}
		}
	}
}
