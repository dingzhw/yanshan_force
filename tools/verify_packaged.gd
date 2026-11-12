extends SceneTree
var failures=0
var checks=0
func verify(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",message)
func _initialize():call_deferred("run")
func run():
	var words=JSON.parse_string(FileAccess.get_file_as_string("res://data/wordpacks/jiangsu-5a-2026.json"))
	verify(words is Dictionary and words.get("entries",[]).size()==175,"standalone PCK contains all 175 textbook records")
	print("PACKAGED_WORDPACK_SHA256 ",FileAccess.get_sha256("res://data/wordpacks/jiangsu-5a-2026.json"))
	var learning=JSON.parse_string(FileAccess.get_file_as_string("res://data/exploration/grade5a.json"))
	verify(learning is Dictionary and learning.has("math") and learning.has("poem"),"standalone PCK includes the new exploration question data")
	for name in ["rifle","crate","rock_0","rock_1","rock_2","rock_3","rock_4","rock_5"]:
		verify(ResourceLoader.exists("res://assets/slice/"+name+".glb"),"packaged model "+name)
	for name in ["ground_color","ground_normal","tree_bark","tree_needles","tree_alpha"]:
		verify(ResourceLoader.exists("res://assets/slice/"+name+".jpg"),"packaged texture "+name)
	verify(FileAccess.file_exists("res://licenses/Slice-CC0-sources.txt"),"standalone PCK carries source and license notices")
	verify(not FileAccess.file_exists("res://tests/smoke.gd"),"development tests excluded from distribution")
	print("PACKAGED_RESOURCE_CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
