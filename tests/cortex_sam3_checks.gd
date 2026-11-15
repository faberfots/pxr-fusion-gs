extends SceneTree
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<2:quit(2);return
	if args.size()>2:CortexAssets.qualification_root=args[2]
	var image:=Image.load_from_file(args[1]);image.convert(Image.FORMAT_RGB8)
	var service:=CortexSegmentationService.new();root.add_child(service)
	var result:Dictionary={};service.completed.connect(func(value):result.assign(value))
	var settings:={"engine":"sam3","sam3_directory":args[0],"confidence":0.25,"mask_opacity":0.45}
	var started:=Time.get_ticks_msec();var frames:=0
	check(service.request(image,"sam3-real-fixture",settings,PackedVector2Array(),PackedInt32Array(),"motorcycle")==OK,"the supplied verified SAM3 pack starts on a private worker")
	while result.is_empty() and Time.get_ticks_msec()-started<300000:
		await process_frame;frames+=1
		if frames%600==0:print("SAM3 PHASE ",service.phase()," elapsed_ms ",Time.get_ticks_msec()-started)
	check(not result.has("error") and result.has("masks"),"SAM3 executes the real image, language encoder and decoder")
	if result.has("error"):print("SAM3 FAILURE ",result.error)
	if result.has("masks"):
		check(result.size==image.get_size() and not result.masks.is_empty(),"text prompting returns at least one real mask at original image dimensions")
		if result.has("preview"):result.preview.save_png("user://sam3-motorcycle-mask.png")
		check(result.get("probe_point",Vector2.INF).is_finite(),"the returned mask supplies a visible foreground point")
	print("SAM3 REAL RESULT ",JSON.stringify({"elapsed_ms":Time.get_ticks_msec()-started,"ui_frames":frames,"masks":result.get("masks",[]).size(),"scores":Array(result.get("scores",PackedFloat32Array()))}))
	if result.get("probe_point",Vector2.INF).is_finite():
		var point:Vector2=result.probe_point
		var box:=Rect2(point-Vector2(32,32),Vector2(64,64)).intersection(Rect2(Vector2.ZERO,Vector2(image.get_size())))
		result.clear();started=Time.get_ticks_msec()
		service.request(image,"sam3-real-fixture",settings,PackedVector2Array(),PackedInt32Array(),"motorcycle",box,true)
		while result.is_empty() and Time.get_ticks_msec()-started<90000:await process_frame
		check(result.has("masks") and result.get("size",Vector2i.ZERO)==image.get_size(),"cached SAM3 embeddings support an actual box-conditioned decoder request")
		result.clear();settings.engine="mobile_sam";started=Time.get_ticks_msec()
		service.request(image,"mobile-after-sam3",settings,PackedVector2Array([point]),PackedInt32Array([1]),"")
		while result.is_empty() and Time.get_ticks_msec()-started<90000:await process_frame
		check(result.get("engine","")=="mobile_sam" and result.get("masks",[]).size()==1,"switching engines releases SAM3 sessions and performs real MobileSAM inference on the same private worker")
	service.release();service.free()
	print("CORTEX SAM3 COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
