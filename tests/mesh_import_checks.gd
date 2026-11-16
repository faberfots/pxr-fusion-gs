extends SceneTree
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func run()->void:
	var paths:=OS.get_cmdline_user_args()
	for path in paths:
		var job:=GSSceneImportJob.new();check(job.start(path)==OK,"native parser starts for "+path.get_file())
		while not job.is_done():await process_frame
		var result:=job.finish()
		check(not result.has("error"),"native parser completes for "+path.get_file())
		if result.has("error"):print(result);continue
		var asset:=GSSceneMesh.new();asset.file_path=path
		check(asset.initialize(result.root,result.fingerprints)==OK and asset.vertex_count>0,"import root owns usable geometry, native materials and exact authored child transforms")
		print("MESH METADATA ",path.get_file()," vertices ",asset.vertex_count," surfaces ",asset.surface_count," transparent ",asset.transparent_surfaces," bounds ",asset.bounds_local)
		asset.free()
	print("MESH IMPORT COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
