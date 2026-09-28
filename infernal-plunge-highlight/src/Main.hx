import hlx.runtime.HlxPrefixControl;
import hlx.runtime.HlxPrefixResult;
import HlxRuntime;
import hlx.runtime.ResolvedMember;
import imgui.ImGui;
import imgui.Enums.ImGuiWindowFlags;
import imgui.Enums.ImGuiCol;
import imgui.Structs.ImVec2;
import Reflect;
import Type;
import Std;
import Math;

@:build(hlx.runtime.Mod.build())
class Main {
	static final SKILL_KIND = "Daggers_Demondash_Skill1";
	static final MARK_STATUSES = ["Daggers_Demondash_Mark", "Status_Chaos_Mark", "Chaos_Mark"];

	static var resolved = false;
	static var resolveFailed = false;
	static var chaosReady = false;

	static var rmGetTarget:ResolvedMember;
	static var rmGetTargetUnit:ResolvedMember;
	static var rmHasStatus:ResolvedMember;
	static var rmHasStatusType:ResolvedMember;

	static var lastDetectTime:Float = 0;
	static var detectInterval:Float = 0.03;
	static var lastChaosState:Bool = false;
	static var markEndTimes:Dynamic = {};

static var imguiRegistered = false;
static var imguiInitAttempted = false;
static var infernalPlungeTex:hl.I64 = 0;

static function main():Void {
	markEndTimes = {};
}

	static function ensureResolved():Bool {
		if (resolved) return true;
		if (resolveFailed) return false;

		var tHero = HlxRuntime.resolveType("ent.Hero");
		var tGo = HlxRuntime.resolveType("ent.GameObject");
		var tSS = HlxRuntime.resolveType("script.SkillScript");
		if (tHero == null || tGo == null) return false;

		rmGetTarget = HlxRuntime.resolveMember(tHero, "getTarget");
		rmGetTargetUnit = HlxRuntime.resolveMember(tHero, "get_targetUnit");
		if (rmGetTarget == null) rmGetTarget = HlxRuntime.resolveMember(tGo, "getTarget");
		rmHasStatus = HlxRuntime.resolveMember(tGo, "hasStatus");
		rmHasStatusType = HlxRuntime.resolveMember(tGo, "hasStatusType");

		if (rmGetTarget == null) {
			resolveFailed = true;
			return false;
		}

		resolved = true;
		return true;
	}

	static function getHero(self:Dynamic):Dynamic {
		try {
			var app = HlxRuntime.resolveType("GameApp");
			if (app != null) {
				var rmGet = HlxRuntime.resolveMember(app, "get");
				if (rmGet != null) {
					var gameApp = HlxRuntime.callResolved(rmGet, []);
					if (gameApp != null) {
						var hero = Reflect.field(gameApp, "hero");
						if (hero != null) return hero;
					}
				}
			}
		} catch (_:Dynamic) {}

		if (self != null && Std.string(Type.typeof(self)).indexOf("TClass") < 0) {
			var hero = Reflect.field(self, "hero");
			if (hero != null) return hero;
			var gui = Reflect.field(self, "gui");
			if (gui != null) {
				var game = Reflect.field(gui, "game");
				if (game != null) {
					hero = Reflect.field(game, "hero");
					if (hero != null) return hero;
				}
			}
		}
		return null;
	}

	static function getTarget(hero:Dynamic):Dynamic {
		if (hero == null) return null;
		if (rmGetTarget != null) {
			try {
				var target = HlxRuntime.callResolved(rmGetTarget, [hero]);
				if (target != null) return target;
			} catch (_:Dynamic) {}
		}
		if (rmGetTargetUnit != null) {
			try {
				var target = HlxRuntime.callResolved(rmGetTargetUnit, [hero]);
				if (target != null) return target;
			} catch (_:Dynamic) {}
		}
		return Reflect.field(hero, "target");
	}

	static function getGameTime():Float {
		try {
			var timerClass = Type.resolveClass("hxd.Timer");
			if (timerClass != null) {
				var t = Reflect.field(timerClass, "lastTimeStamp");
				if (t != null && (t:Float) > 0) return t;
			}
		} catch (_:Dynamic) {}
		try {
			var timerClass = Type.resolveClass("hxd.Timer");
			if (timerClass != null) {
				var t = Reflect.field(timerClass, "elapsedTime");
				if (t != null && (t:Float) > 0) return t;
			}
		} catch (_:Dynamic) {}
		try return haxe.Timer.stamp() catch (_:Dynamic) return Date.now().getTime() / 1000.0;
	}

	static function extractClassName(obj:Dynamic):String {
		var name = Reflect.field(obj, "name") ?? Reflect.field(obj, "statusName") ?? "";
		if (name != "" && name != "unknown") return name;
		try {
			var cls = Type.getClass(obj);
			if (cls != null) name = Type.getClassName(cls);
		} catch (_:Dynamic) {}
		if (name == "" || name == "unknown" || name == "st.skill.Status") {
			var str = Std.string(obj);
			var hashIdx = str.indexOf("#");
			if (hashIdx > 0) name = str.substring(0, hashIdx);
		}
		return name;
	}

	static function targetHasMark(target:Dynamic):Bool {
		if (target == null) return false;

		var now = getGameTime();
		var key = Std.string(target);
		var found = false;

		// Method 1: target.statuses - statuses ON this target (most accurate)
		try {
			var statuses = Reflect.field(target, "statuses");
			if (statuses != null) {
				var arrayObj = statuses;
				var proxyArray = Reflect.field(arrayObj, "array");
				if (proxyArray != null) {
					var dynArray = Reflect.field(proxyArray, "array");
					if (dynArray != null) arrayObj = dynArray;
				}
				var getDyn = Reflect.field(arrayObj, "getDyn");
				if (getDyn != null) {
					for (i in 0...100) {
						var status = null;
						try {
							status = Reflect.callMethod(arrayObj, getDyn, [i]);
						} catch (_:Dynamic) {}
						if (status == null) break;
						var name = extractClassName(status);
						for (mark in MARK_STATUSES) {
							if (name == mark) {
// Simple: set 6s on first detection, then count down
							var existing = Reflect.field(markEndTimes, key);
							if (existing == null || existing <= now) {
								// First detection or expired
								Reflect.setField(markEndTimes, key, now + 6.0);
							} else if (existing - now < 1.0) {
								// Mark detected but timer nearly expired = likely refreshed
								Reflect.setField(markEndTimes, key, now + 6.0);
							}
							found = true;
							}
						}
					}
				}
			}
		} catch (_:Dynamic) {}

		return found;
	}

	static function periodicDetect(self:Dynamic):Bool {
		var now = getGameTime();
		if (now - lastDetectTime < detectInterval) return chaosReady;
		lastDetectTime = now;
		return detectChaos(self);
	}

	static function detectChaos(self:Dynamic):Bool {
		if (!ensureResolved()) return false;

		var hero = getHero(self);
		if (hero == null) return false;

		var target = getTarget(hero);
		if (target == null) return false;

		var has = targetHasMark(target);
		var now = getGameTime();

		if (!has) {
			Reflect.deleteField(markEndTimes, Std.string(target));
		}

		// Use per-target markEndTime
		var key = Std.string(target);
		var markEndTime = Reflect.field(markEndTimes, key);
		var stableHas = has || (markEndTime != null && markEndTime > now + 0.02);

		if (stableHas != lastChaosState) {
			lastChaosState = stableHas;
		}
		return stableHas;
	}

static function ensureImGui():Void {
	if (imguiRegistered || imguiInitAttempted) return;
	imguiInitAttempted = true;
	try {
		ImGui.register("infernal-plunge-highlight", drawOverlay);
		imguiRegistered = true;
	} catch (_:Dynamic) {
		imguiRegistered = false;
	}
}

static function toBytes(s:String):hl.Bytes {
	var b = new hl.Bytes(s.length + 1);
	for (i in 0...s.length) b.setUI8(i, s.charCodeAt(i));
	b.setUI8(s.length, 0);
	return b;
}

static function getSkillIconTexture(skillId:String):hl.I64 {
	if (infernalPlungeTex.toInt() != 0) return infernalPlungeTex;
	try {
		var skillsType = HlxRuntime.resolveType("ent.Skills");
		if (skillsType != null) {
			var rmGetIcon = HlxRuntime.resolveMember(skillsType, "getSkillIcon");
			if (rmGetIcon != null) {
				var tex = HlxRuntime.callResolved(rmGetIcon, [skillId]);
				if (tex != 0) {
					infernalPlungeTex = tex;
					return tex;
				}
			}
		}
	} catch (_:Dynamic) {}
	return 0;
}

static function drawOverlay():Void {
	var now = getGameTime();
	if (!chaosReady) return;
	try {
		if (ImGui.begin("Infernal Plunge Highlight", null, ImGuiWindowFlags.NoTitleBar | ImGuiWindowFlags.NoResize | ImGuiWindowFlags.AlwaysAutoResize)) {
			var hero = getHero(null);
			var target = (hero != null) ? getTarget(hero) : null;
			var key = (target != null) ? Std.string(target) : null;
			var markEndTime = (key != null) ? Reflect.field(markEndTimes, key) : null;
			var remaining = (markEndTime != null) ? markEndTime - now : 0;
			if (remaining < 0) remaining = 0;
			if (remaining > 6) remaining = 6;

			// Draw Infernal Plunge icon
			var iconTex = getSkillIconTexture("Daggers_Demondash_Skill1");
			if (iconTex.toInt() == 0) {
				iconTex = getSkillIconTexture("Rogue_InfPlunge");
			}
			if (iconTex.toInt() == 0) {
				iconTex = getSkillIconTexture("infernal plunge");
			}
			if (iconTex.toInt() != 0) {
				ImGui.image(iconTex.toInt(), new ImVec2(24, 24));
				ImGui.sameLine();
				ImGui.text("CHAOS MARK ACTIVE");
			} else {
				// Fallback: colored square + text if texture not found
				ImGui.pushStyleColor(ImGuiCol.Text, 0xFF6600FF);
				ImGui.text("◆");
				ImGui.popStyleColor();
				ImGui.sameLine();
				ImGui.text("CHAOS MARK ACTIVE");
			}
			ImGui.separator();

			// Cooldown number - red
			var timeText = Math.round(remaining * 10) / 10 + "s";
			ImGui.pushStyleColor(ImGuiCol.Text, 0xFF0000FF);
			ImGui.text(timeText);
			ImGui.popStyleColor();

			ImGui.separator();
			ImGui.text("Infernal Plunge READY!");

			ImGui.end();
		}
	} catch (_:Dynamic) {
		imguiRegistered = false;
	}
}

	@:hlx.postfix(GameApp.update)
	static function onGameAppUpdate(instance:Dynamic, dt:Float, result:Void):Void {
		ensureImGui();
		try {
			chaosReady = periodicDetect(instance);
		} catch (_:Dynamic) {}
	}
}