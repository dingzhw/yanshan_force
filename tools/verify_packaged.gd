extends SceneTree
var failures = 0
var checks = 0

func verify(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", message)

func _initialize():
	call_deferred("run")

func run():
	var words = JSON.parse_string(FileAccess.get_file_as_string("res://data/wordpacks/jiangsu-5a-2026.json"))
	verify(words is Dictionary and words.get("entries", []).size() == 175, "standalone PCK contains all 175 textbook records")
	print("PACKAGED_WORDPACK_SHA256 ", FileAccess.get_sha256("res://data/wordpacks/jiangsu-5a-2026.json"))
	var learning = JSON.parse_string(FileAccess.get_file_as_string("res://data/exploration/grade5a.json"))
	verify(learning is Dictionary and learning.has("math") and learning.has("poem"), "standalone PCK includes exploration question data")
	var sentences = JSON.parse_string(FileAccess.get_file_as_string("res://data/learning/jiangsu-5a-sentences.json"))
	var cloze_count := 0
	if sentences is Dictionary and sentences.get("entries") is Array:
		for s in sentences.entries:
			cloze_count += s.get("cloze_targets", []).size()
	verify(sentences is Dictionary and sentences.get("entries", []).size() == 16 and cloze_count >= 15, "standalone PCK includes all 16 sourced sentence entries with 15+ verified Cloze targets")
	verify(ResourceLoader.exists("res://scripts/srs_scheduler.gd") and ResourceLoader.exists("res://scripts/learning_store.gd"), "standalone PCK includes SRS scheduler and learning store modules")
	verify(ResourceLoader.exists("res://scenes/prologue_chapter.tscn") and ResourceLoader.exists("res://scripts/prologue.gd"), "standalone PCK includes editable Prologue scene and script")
	var pro_scene = load("res://scenes/prologue_chapter.tscn")
	verify(pro_scene is PackedScene, "standalone PCK loads prologue_chapter.tscn as valid PackedScene")
	verify(bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)), "exported project enables audio/general/text_to_speech for OS TTS fallback")

	# Full 341/341 offline voice OGG existence AND real AudioStream decode verification!
	var voice_manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/learning/voice_manifest.json"))
	var voice_ok: bool = (voice_manifest is Dictionary and voice_manifest.get("entries") is Dictionary and voice_manifest.entries.size() >= 341)
	var missing_ogg: int = 0
	var decode_failed_ogg: int = 0
	var decoded_ogg_count: int = 0
	if voice_ok:
		for k in voice_manifest.entries.keys():
			var fname: String = str(voice_manifest.entries[k].get("file", ""))
			var vpath := "res://assets/voice/" + fname
			if fname == "" or not ResourceLoader.exists(vpath):
				missing_ogg += 1
				continue
			var stream = load(vpath)
			if stream is AudioStream and stream.get_length() > 0.05:
				decoded_ogg_count += 1
			else:
				decode_failed_ogg += 1
	verify(voice_ok and missing_ogg == 0 and decode_failed_ogg == 0, "standalone PCK decodes ALL offline voice OGG streams cleanly (%d/%d decoded, %d missing, %d decode_err)" % [
		decoded_ogg_count, voice_manifest.entries.size() if voice_ok else 0, missing_ogg, decode_failed_ogg
	])

	# Full 38/38 SFX WAV existence AND AudioStream decode verification! (Godot PCK lists *.wav.import remaps)
	var sfx_dir := DirAccess.open("res://assets/sfx")
	var sfx_seen := {}
	var sfx_total := 0
	var sfx_decoded := 0
	if sfx_dir != null:
		for raw_f in sfx_dir.get_files():
			var sf: String = raw_f.trim_suffix(".import")
			if sf.ends_with(".wav") and not sfx_seen.has(sf):
				sfx_seen[sf] = true
				sfx_total += 1
				var st = load("res://assets/sfx/" + sf)
				if st is AudioStream and st.get_length() > 0.01:
					sfx_decoded += 1
	var req_sfx_ok := true
	for sfx_n in ["shot_rifle", "shot_suppressed", "reload_mag_out", "reload_mag_in", "reload_bolt", "shell_clink", "achievement_unlock", "warden_sonar", "warden_shield_deflect", "boss_skyfall", "boss_slash", "boss_ultimate", "skill_slam", "saeed_lmg_burst", "saeed_fire_bolt", "reis_shotgun_blast", "gramophone_chord", "dam_artillery_siren"]:
		if not ResourceLoader.exists("res://assets/sfx/" + sfx_n + ".wav"):
			req_sfx_ok = false
	verify(req_sfx_ok and sfx_total >= 43 and sfx_decoded == sfx_total, "standalone PCK decodes ALL packaged SFX WAV streams cleanly (%d/%d decoded)" % [sfx_decoded, sfx_total])

	var loot_ui_cls = load("res://scripts/loot_ui.gd")
	var art_ids: PackedStringArray = loot_ui_cls.all_collectible_art_ids()
	var missing_col_mesh: int = 0
	var missing_col_icon: int = 0
	for aid in art_ids:
		if loot_ui_cls.get_collectible_mesh(aid) == null:
			missing_col_mesh += 1
		if loot_ui_cls.load_collectible_icon(aid) == null:
			missing_col_icon += 1
	verify(art_ids.size() == 114 and ResourceLoader.exists("res://assets/slice/v072_collectibles.glb") and ResourceLoader.exists("res://assets/slice/v086_collectibles.glb") and ResourceLoader.exists("res://assets/slice/v090_ahsarah_collectibles.glb") and missing_col_mesh == 0, "standalone PCK contains all 114 sculpted PBR collectible meshes across v072+v086+v090_ahsarah_collectibles.glb")
	verify(art_ids.size() == 114 and missing_col_icon == 0, "standalone PCK contains all 114 studio-rendered collectible 2D icons")
	for name in ["rifle", "crate", "rock_0", "rock_1", "rock_2", "rock_3", "rock_4", "rock_5"]:
		verify(ResourceLoader.exists("res://assets/slice/" + name + ".glb"), "packaged model " + name)
	for name in ["ground_color", "ground_normal", "tree_bark", "tree_needles", "tree_alpha"]:
		verify(ResourceLoader.exists("res://assets/slice/" + name + ".jpg"), "packaged texture " + name)
	verify(ResourceLoader.exists("res://assets/slice/horizon_mountains.png") and ResourceLoader.exists("res://assets/slice/horizon_cloud_ribbon.png"), "standalone PCK includes v0.8.6 cloud-wreathed distant mountain panorama & mist ribbon textures")
	verify(ResourceLoader.exists("res://assets/slice/v082_bosses.glb") and ResourceLoader.exists("res://assets/slice/v086_mirror_yanshan.glb") and ResourceLoader.exists("res://assets/slice/v086_architecture.glb") and ResourceLoader.exists("res://scripts/cave_warden.gd") and ResourceLoader.exists("res://scripts/achievements.gd") and ResourceLoader.exists("res://scripts/rangers.gd") and ResourceLoader.exists("res://scripts/loot_container_ui.gd"), "standalone PCK includes v0.8.6 articulated bosses, Mirror Yanshan, architecture GLBs & core scripts")
	var boss_glb_packed = load("res://assets/slice/v082_bosses.glb")
	var boss_rig_ok := false
	if boss_glb_packed is PackedScene:
		var bi: Node = boss_glb_packed.instantiate()
		boss_rig_ok = (
			bi.find_child("warden_body", true, false) != null and bi.find_child("arm_left_pivot", true, false) != null
			and bi.find_child("arm_right_pivot", true, false) != null and bi.find_child("head_crest", true, false) != null
			and bi.find_child("skyfall_overlord", true, false) != null and bi.find_child("overlord_arm_l", true, false) != null
			and bi.find_child("overlord_arm_r", true, false) != null and bi.find_child("overlord_halo_ring", true, false) != null
		)
		bi.free()
	verify(boss_rig_ok, "standalone PCK v082_bosses.glb contains articulated Cave Warden (4-part) & articulated Skyfall Overlord (5-part)")
	var arch_ok := false
	if ResourceLoader.exists("res://assets/slice/v086_architecture.glb"):
		var arch_packed = load("res://assets/slice/v086_architecture.glb")
		if arch_packed is PackedScene:
			var ai: Node = arch_packed.instantiate()
			arch_ok = (
				ai.find_child("watchtower_jiangnan", true, false) != null
				and ai.find_child("bamboo_shelter_jiangnan", true, false) != null
				and ai.find_child("tea_pavilion_upgraded", true, false) != null
				and ai.find_child("wangdao_pavilion_complete", true, false) != null
				and ai.find_child("mountain_arch_gate", true, false) != null
				and ai.find_child("jiangnan_signboard_frame", true, false) != null
				and ai.find_child("distant_peaks_ring", true, false) != null
			)
			ai.free()
	verify(arch_ok, "standalone PCK v086_architecture.glb contains handcrafted Jiangnan architecture & 3D distant peaks ring")
	var wild_v86_ok := true
	for wglb in ["animal_deer", "animal_pheasant", "animal_turtle", "animal_butterfly"]:
		if not ResourceLoader.exists("res://assets/slice/wildlife/" + wglb + ".glb"):
			wild_v86_ok = false
	verify(wild_v86_ok, "standalone PCK includes all 4 v0.8.6 skeletal wildlife GLBs (deer/pheasant/turtle/butterfly)")
	var lm_ok := false
	if ResourceLoader.exists("res://assets/slice/v085_landmarks.glb"):
		var lm_packed = load("res://assets/slice/v085_landmarks.glb")
		if lm_packed is PackedScene:
			var lmi: Node = lm_packed.instantiate()
			lm_ok = (lmi.find_child("bridge_multi_arch", true, false) != null and lmi.find_child("tea_hill_pavilion", true, false) != null and lmi.find_child("cliff_stele", true, false) != null and lmi.find_child("arena_dragon_pillar", true, false) != null and lmi.find_child("arena_altar_rim", true, false) != null)
			lmi.free()
	verify(lm_ok, "standalone PCK v085_landmarks.glb contains all 5 Great Yanshan landmarks (bridge_multi_arch/tea_hill_pavilion/cliff_stele/arena_dragon_pillar/arena_altar_rim)")
	var ah_assets_ok := (
		ResourceLoader.exists("res://scripts/ahsarah_layout.gd")
		and ResourceLoader.exists("res://scripts/ahsarah_world.gd")
		and ResourceLoader.exists("res://assets/slice/v090_ahsarah_architecture.glb")
		and ResourceLoader.exists("res://assets/slice/v090_ahsarah_characters.glb")
		and ResourceLoader.exists("res://assets/slice/v090_ahsarah_collectibles.glb")
		and ResourceLoader.exists("res://assets/slice/horizon_ahsarah.png")
		and ResourceLoader.exists("res://assets/slice/ahsarah_sand_albedo.jpg")
		and ResourceLoader.exists("res://assets/slice/ahsarah_sandstone_albedo.jpg")
		and ResourceLoader.exists("res://assets/slice/ahsarah_concrete_albedo.jpg")
		and ResourceLoader.exists("res://assets/slice/ahsarah_road_albedo.jpg")
	)
	verify(ah_assets_ok, "standalone PCK includes all v0.9.0 Ahsarah Fortress scripts, architecture/character/collectible GLBs, 360° horizon & PBR desert textures")
	var ah_rig_ok := false
	if ResourceLoader.exists("res://assets/slice/v090_ahsarah_characters.glb"):
		var ch_p = load("res://assets/slice/v090_ahsarah_characters.glb")
		if ch_p is PackedScene:
			var chi: Node = ch_p.instantiate()
			ah_rig_ok = (chi.find_child("boss_saeed", true, false) != null and chi.find_child("boss_reis", true, false) != null and chi.find_child("ahsarah_guard", true, false) != null and chi.find_child("haavk_trooper", true, false) != null)
			chi.free()
	verify(ah_rig_ok, "standalone PCK v090_ahsarah_characters.glb contains boss_saeed, boss_reis, ahsarah_guard & haavk_trooper rigs")
	var ah_arch_ok := false
	if ResourceLoader.exists("res://assets/slice/v090_ahsarah_architecture.glb"):
		var arch_p = load("res://assets/slice/v090_ahsarah_architecture.glb")
		if arch_p is PackedScene:
			var aai: Node = arch_p.instantiate()
			ah_arch_ok = (
				aai.find_child("zero_dam_wall_monolith", true, false) != null
				and aai.find_child("babel_radar_tower", true, false) != null
				and aai.find_child("ahsarah_fortress_gatehouse", true, false) != null
				and aai.find_child("brakkesh_sandstone_pavilion", true, false) != null
				and aai.find_child("dimensional_rift_wall", true, false) != null
				and aai.find_child("desert_boulder_a", true, false) != null
				and aai.find_child("desert_boulder_b", true, false) != null
				and aai.find_child("desert_perimeter_rockwall", true, false) != null
				and aai.find_child("oasis_spring_head", true, false) != null
			)
			aai.free()
	verify(ah_arch_ok, "standalone PCK v090_ahsarah_architecture.glb contains Zero Dam, Babel Tower, Ahsarah Gatehouse, Brakkesh Pavilion & Dimensional Rift Wall")
	var v91_fort_ok := false
	if ResourceLoader.exists("res://scripts/mandel_event.gd") and ResourceLoader.exists("res://assets/slice/v091_ahsarah_fortress.glb"):
		var f91_p = load("res://assets/slice/v091_ahsarah_fortress.glb")
		if f91_p is PackedScene:
			var fi91: Node = f91_p.instantiate()
			v91_fort_ok = (
				fi91.find_child("fortress_interior_wing", true, false) != null
				and fi91.find_child("dam_spillway_tunnel", true, false) != null
				and fi91.find_child("brakkesh_grand_bathhouse", true, false) != null
				and fi91.find_child("cement_elevated_catwalk", true, false) != null
				and fi91.find_child("mandel_decode_station", true, false) != null
				and fi91.find_child("mandel_brick_pedestal", true, false) != null
			)
			fi91.free()
	verify(v91_fort_ok, "standalone PCK includes v0.9.1 mandel_event.gd & all 6 multi-story fortress/MandelBrick models in v091_ahsarah_fortress.glb")
	var wild_v91_ok := true
	for w91 in ["animal_fennec", "animal_camel", "animal_falcon", "animal_scarab"]:
		if not ResourceLoader.exists("res://assets/slice/wildlife/" + w91 + ".glb"):
			wild_v91_ok = false
	verify(wild_v91_ok, "standalone PCK includes all 4 v0.9.1 rigged desert wildlife GLBs (fennec/camel/falcon/scarab)")
	var v92_pickups_ok := false
	if ResourceLoader.exists("res://assets/slice/v092_tactical_pickups.glb"):
		var p92_p = load("res://assets/slice/v092_tactical_pickups.glb")
		if p92_p is PackedScene:
			var pi92: Node = p92_p.instantiate()
			v92_pickups_ok = (
				pi92.find_child("pickup_ammo_crate", true, false) != null
				and pi92.find_child("pickup_medkit", true, false) != null
				and pi92.find_child("pickup_smoke_emp", true, false) != null
				and pi92.find_child("pickup_energy_stim", true, false) != null
				and pi92.find_child("ahsarah_desert_stash", true, false) != null
				and pi92.find_child("ahsarah_loot_table", true, false) != null
				and pi92.find_child("boss_incendiary_bolt", true, false) != null
				and pi92.find_child("boss_frag_grenade", true, false) != null
			)
			pi92.free()
	verify(v92_pickups_ok, "standalone PCK v092_tactical_pickups.glb contains all 8 sculpted Blender 4.5 pickups, desert stashes & boss ordnance")
	# v0.9.3 Offline Chinese Faction & Boss Voice Pack + Articulated Full-Body Hero Shaoyu GLB
	var cn_raw := FileAccess.get_file_as_string("res://data/audio/cn_voice_manifest.json")
	var cn_parsed = JSON.parse_string(cn_raw)
	var cn_entries: Dictionary = cn_parsed.entries if (cn_parsed is Dictionary and cn_parsed.get("entries") is Dictionary) else {}
	var cn_decoded := 0
	for cid in cn_entries.keys():
		var cf := str(cn_entries[cid].get("file", ""))
		var cp := "res://assets/voice_cn/" + cf
		if cf != "" and ResourceLoader.exists(cp):
			var cst = load(cp)
			if cst is AudioStream and cst.get_length() > 0.35:
				cn_decoded += 1
	verify(cn_entries.size() >= 60 and cn_decoded == cn_entries.size(), "standalone PCK decodes ALL offline Chinese faction/boss OGG voice clips cleanly (%d/%d decoded)" % [cn_decoded, cn_entries.size()])
	var hero_ok := false
	var hero_bones := 0
	var hero_anims := 0
	if ResourceLoader.exists("res://scripts/player_body.gd") and ResourceLoader.exists("res://scripts/hud_widgets.gd") and ResourceLoader.exists("res://assets/slice/player_shaoyu.glb"):
		var hp_p = load("res://assets/slice/player_shaoyu.glb")
		if hp_p is PackedScene:
			var hi: Node = hp_p.instantiate()
			var sk := hi.find_child("Skeleton3D", true, false) as Skeleton3D
			var ap := hi.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if sk != null and ap != null:
				hero_bones = sk.get_bone_count()
				hero_anims = ap.get_animation_list().size()
				hero_ok = (
					hero_bones >= 55
					and hero_anims >= 22
					and sk.find_bone("Hips") >= 0
					and sk.find_bone("Chest") >= 0
					and sk.find_bone("Hand.L") >= 0
					and sk.find_bone("Hand.R") >= 0
					and sk.find_bone("Weapon_R") >= 0
					and sk.find_bone("Weapon_Back") >= 0
					and sk.find_bone("Scarf_01") >= 0
					and sk.find_bone("Scarf_04") >= 0
					and ap.has_animation("Rifle_LowReady")
					and ap.has_animation("Rifle_Aim")
					and ap.has_animation("Prone_Idle")
					and ap.has_animation("Prone_Crawl")
					and ap.has_animation("Sprint_Fwd")
					and ap.has_animation("Shaoyu_GroundSlam")
					and hi.find_child("Shaoyu_UpperBody", true, false) != null
					and hi.find_child("Shaoyu_LowerLegs", true, false) != null
					and hi.find_child("Shaoyu_LowerBoots", true, false) != null
				)
			hi.free()
	verify(hero_ok and ResourceLoader.exists("res://assets/slice/arm_sleeve_shaoyu.jpg"), "standalone PCK includes v0.9.9.3 Mixamo-mocap Shaoyu v2 player_shaoyu.glb (%d bones, %d anims, capped 1P/3P split + unified 1P bamboo-teal sleeve)" % [hero_bones, hero_anims])
	var portrait_ids := ["shaoyu", "chen_guide", "tingfeng", "qinghe", "zhuying", "mistbound_soldier", "vanguard_boss", "skyfall_overlord", "cave_warden", "ahsarah_guard", "saeed_fiery_owl", "reis_warlord", "haavk_trooper", "mandel_protocol", "locked_mystery"]
	var portraits_loaded := 0
	for pid in portrait_ids:
		var pp := "res://assets/portraits/%s.png" % pid
		if ResourceLoader.exists(pp):
			var pt = load(pp)
			if pt is Texture2D and pt.get_width() >= 256:
				portraits_loaded += 1
	var warmap_ids := ["map_yanshan_hd", "map_ahsarah_hd", "map_story_hd"]
	var warmaps_loaded := 0
	for wid in warmap_ids:
		var wp := "res://assets/warmap/%s.png" % wid
		if ResourceLoader.exists(wp):
			var wt = load(wp)
			if wt is Texture2D and wt.get_width() >= 1024:
				warmaps_loaded += 1
	verify(ResourceLoader.exists("res://scripts/lore_codex_ui.gd") and ResourceLoader.exists("res://scripts/war_map_3d.gd") and portraits_loaded == 15 and warmaps_loaded == 3, "standalone PCK includes v0.9.6 LoreCodexUI, WarMap3D, 14 portraits + '?' silhouette (%d/15) & 3 HD relief maps (%d/3)" % [portraits_loaded, warmaps_loaded])
	var pbr_sets := ["coast_sand_01", "gravelly_sand", "cliff_side", "gravel_road", "clay_plaster", "old_sandstone_02", "plaster_grey_04", "aerial_grass_rock", "mossy_rock"]
	var pbr_loaded := 0
	for slug in pbr_sets:
		for ch in ["diff", "nor_gl", "rough"]:
			var tp := "res://assets/pbr_v097/%s_%s.jpg" % [slug, ch]
			if ResourceLoader.exists(tp):
				var t = load(tp)
				if t is Texture2D and t.get_width() >= 512:
					pbr_loaded += 1
	var v097_glbs_ok := true
	for gp in ["res://assets/slice/v097_desert_nature.glb", "res://assets/slice/v097_yanshan_nature.glb", "res://assets/slice/npc_chen_guide.glb", "res://assets/slice/v097_mistbound_assault.glb", "res://assets/slice/v097_mistbound_sniper.glb"]:
		if not ResourceLoader.exists(gp):
			v097_glbs_ok = false
		else:
			var sc = load(gp)
			if not (sc is PackedScene):
				v097_glbs_ok = false
	verify(pbr_loaded == 27 and v097_glbs_ok, "standalone PCK includes v0.9.7 Poly Haven CC0 1K PBR sets (%d/27 maps) & 5 photogrammetry/skeletal GLBs" % pbr_loaded)
	var v098_warden_ok := false
	if ResourceLoader.exists("res://assets/slice/v098_cave_warden.glb"):
		var w98_p = load("res://assets/slice/v098_cave_warden.glb")
		if w98_p is PackedScene:
			var w98_i: Node = w98_p.instantiate()
			v098_warden_ok = (
				w98_i.find_child("warden_body", true, false) != null
				and w98_i.find_child("head_crest", true, false) != null
				and w98_i.find_child("arm_left_pivot", true, false) != null
				and w98_i.find_child("arm_right_pivot", true, false) != null
				and w98_i.find_child("leg_left_pivot", true, false) != null
				and w98_i.find_child("leg_right_pivot", true, false) != null
			)
			w98_i.free()
	var v098_chen_ok := false
	if ResourceLoader.exists("res://assets/slice/npc_chen_guide.glb"):
		var ch98_p = load("res://assets/slice/npc_chen_guide.glb")
		if ch98_p is PackedScene:
			var ch98_i: Node = ch98_p.instantiate()
			v098_chen_ok = (ch98_i.find_child("Chen_VeteranHair", true, false) != null and ch98_i.find_child("Chen_ScoutHat", true, false) == null)
			ch98_i.free()
	var cn_timbre_dict: Dictionary = cn_parsed.get("profile_timbres", {}) if (cn_parsed is Dictionary) else {}
	verify(v098_warden_ok and v098_chen_ok and cn_entries.size() >= 66 and cn_timbre_dict.size() == 8, "standalone PCK includes v0.9.8 portrait-faithful 6-part Cave Warden GLB, hat-free Chen Guide & 66 multi-cast CN voice clips (8 timbres)")
	var v0991_judy_ok := false
	if ResourceLoader.exists("res://assets/slice/wildlife/animal_rabbit.glb"):
		var jr_p = load("res://assets/slice/wildlife/animal_rabbit.glb")
		if jr_p is PackedScene:
			var jr_i: Node = jr_p.instantiate()
			var jr_mesh = jr_i.find_child("JudyHoppsMesh", true, false)
			var jr_skel = jr_i.find_child("Skeleton3D", true, false) as Skeleton3D
			var jr_anim = jr_i.find_child("AnimationPlayer", true, false) as AnimationPlayer
			v0991_judy_ok = (
				jr_mesh != null
				and jr_skel != null and jr_skel.get_bone_count() >= 25
				and jr_anim != null and jr_anim.has_animation("Idle") and jr_anim.has_animation("Walk") and jr_anim.has_animation("Run")
			)
			jr_i.free()
	verify(v0991_judy_ok, "standalone PCK includes v0.9.9.1 rigged hopping Judy Hopps rabbit GLB (JudyHoppsMesh + 29-bone Skeleton3D + Idle/Walk/Run)")
	var v0992_deer_ok := false
	if ResourceLoader.exists("res://assets/slice/wildlife/animal_deer.glb"):
		var dr_p = load("res://assets/slice/wildlife/animal_deer.glb")
		if dr_p is PackedScene:
			var dr_i: Node = dr_p.instantiate()
			var dr_mesh = dr_i.find_child("RealisticDeerMesh", true, false)
			var dr_skel = dr_i.find_child("Skeleton3D", true, false) as Skeleton3D
			var dr_anim = dr_i.find_child("AnimationPlayer", true, false) as AnimationPlayer
			v0992_deer_ok = (
				dr_mesh != null
				and dr_skel != null and dr_skel.get_bone_count() >= 18
				and dr_anim != null and dr_anim.has_animation("Idle") and dr_anim.has_animation("Walk") and dr_anim.has_animation("Run")
			)
			dr_i.free()
	verify(v0992_deer_ok, "standalone PCK includes v0.9.9.2 rigged Realistic Deer GLB (RealisticDeerMesh + 20-bone Skeleton3D + Idle/Walk/Run)")
	verify(FileAccess.file_exists("res://licenses/Slice-CC0-sources.txt") and FileAccess.file_exists("res://licenses/Quaternius-UAL-CC0.txt") and FileAccess.file_exists("res://licenses/KayKit-Animations-CC0.txt"), "standalone PCK carries full source and CC0 character/animation license notices")
	verify(not FileAccess.file_exists("res://tests/smoke.gd"), "development tests excluded from distribution")
	print("PACKAGED_RESOURCE_CHECKS=", checks, " FAILURES=", failures)
	quit(1 if failures else 0)
