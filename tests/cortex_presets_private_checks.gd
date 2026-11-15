extends SceneTree
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	CortexAssets.qualification_root=args[0]
	var brain:Node=root.get_node("SpatialIntelligence")
	var previous:=SIConfig.settings().experience();var original:=SIConfig.settings().snapshot()
	var camera:=Camera3D.new();root.add_child(camera);camera.make_current()
	var result:={"response":"","error":""}
	brain.analysis_completed.connect(func(value):result.response=value)
	brain.analysis_failed.connect(func(value):result.error=value)
	brain.select_preset("scene");brain.policy.local_enabled=false;brain.policy.cloud_enabled=false
	brain.analyze_scene("Reply with the single word ready.")
	check(not result.error.is_empty() and not brain.local_runtime.is_running(),"ordinary analysis remains denied without consent even with a private preset selected")
	result.error=""
	brain.analyze_privately("Reply with the single word ready.")
	check(brain._is_analyzing and brain.policy.local_enabled and not brain.policy.cloud_enabled and not brain.policy.allows_action(),"explicit Start & ask privately authorizes only local read-only scene information")
	var generation:int=brain._generation
	SIConfig.settings().update_experience("scene",true)
	check(brain._generation==generation and brain._is_analyzing,"opening plain-language help does not cancel or restart the pending private question")
	brain.cancel_analysis()
	var deadline:=Time.get_ticks_msec()+120000
	while brain.local_runtime.is_starting() and Time.get_ticks_msec()<deadline:await process_frame
	for i in range(5):await process_frame
	check(result.response.is_empty() and not brain._is_analyzing,"cancelling during startup cannot send the pending question when the model becomes ready")
	brain.analyze_privately("Reply with the single word ready.")
	deadline=Time.get_ticks_msec()+100000
	while brain._is_analyzing and Time.get_ticks_msec()<deadline:await process_frame
	print("GUIDED PRIVATE RESPONSE ",result.response," ERROR ",result.error)
	check(not result.response.is_empty() and result.error.is_empty(),"guided private question completes real bundled Qwen inference without provider or path setup")
	check(SIConfig.settings().snapshot()==original and not brain.policy.cloud_enabled and not brain.policy.allows_action(),"private workflow preserves advanced settings and never grants cloud transmission or scene commands")
	brain.local_runtime.stop();SIConfig.settings().update_experience(previous.preset,previous.help_open);camera.free()
	print("CORTEX PRIVATE PRESET COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
