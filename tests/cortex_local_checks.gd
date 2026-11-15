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
	check(NativeMLBridge.availability().available,"portable MobileSAM and runtime resolve without machine-specific paths")
	var profile:=CortexProviders.profile("compatible");profile.id="vault-check-"+str(Time.get_ticks_usec())
	profile.credential_source="vault"
	var secret:="synthetic-local-credential-"+str(Time.get_ticks_usec())
	check(CortexCredentials.store(profile,secret)==OK and CortexCredentials.resolve(profile)==secret,"Windows credential store writes and reads a synthetic secret through the native API")
	var changed:=profile.duplicate();changed.endpoint="http://127.0.0.1:9999/v1"
	check(CortexCredentials.resolve(changed).is_empty(),"vault credentials remain bound to the configured destination")
	CortexCredentials.forget(profile)
	check(CortexCredentials.resolve(profile).is_empty(),"forget removes the actual OS credential")
	var service:=CortexSegmentationService.new();root.add_child(service)
	var image:=Image.create(640,384,false,Image.FORMAT_RGB8);image.fill(Color.WHITE)
	for y in range(384):
		for x in range(640):
			if pow((x-180.0)/110.0,2)+pow((y-190.0)/120.0,2)<=1.0:image.set_pixel(x,y,Color(0.8,0.1,0.1))
	var result:Dictionary={};service.completed.connect(func(value):result.assign(value))
	var vision:={"engine":"mobile_sam","sam3_directory":"bundle://sam3","confidence":0.25}
	check(service.request(image,"mobile-worker",vision,PackedVector2Array([Vector2(180,190)]),PackedInt32Array([1]),"")==OK,"MobileSAM starts on the private worker using the portable bundle")
	var started:=Time.get_ticks_msec();var frames:=0
	while result.is_empty() and Time.get_ticks_msec()-started<90000:await process_frame;frames+=1
	if result.has("error"):print("MOBILE ERROR ",result.error)
	check(result.get("masks",[]).size()==1 and result.masks[0][190*640+180]>0 and frames>10,"real worker inference returns the foreground mask while the main loop continues")
	result.clear()
	service.request(image,"cancelled-capture",vision,PackedVector2Array([Vector2(180,190)]),PackedInt32Array([1]),"");service.cancel()
	while service.is_busy():await process_frame
	for i in range(5):await process_frame
	check(result.is_empty(),"cancelled inference cannot deliver stale masks")
	service.release();service.free()
	var runtime:=CortexLocalRuntime.new();runtime.policy=AIAccessPolicy.new();root.add_child(runtime)
	runtime.policy.configuration_enabled=false
	check(runtime.start_bundled()==ERR_UNAUTHORIZED and not runtime.is_running(),"managed roles cannot launch local processes without configuration permission")
	runtime.policy.configuration_enabled=true
	check(runtime.start_bundled()==OK,"verified bundled Qwen starts explicitly through its owned CPU process")
	started=Time.get_ticks_msec()
	while runtime.is_starting() and Time.get_ticks_msec()-started<120000:await process_frame
	print("QWEN STARTUP ",runtime.message)
	check(runtime.is_running() and runtime.message.begins_with("Ready"),"bundled Qwen becomes ready on its loopback-only endpoint")
	var client:=LLMClient.new();client.policy=runtime.policy;root.add_child(client)
	var reply:={"response":"","error":""}
	client.response_received.connect(func(value):reply.response=value)
	client.error_occurred.connect(func(value):reply.error=value)
	var qwen:=CortexProviders.profile("qwen");qwen.max_tokens=24
	client.send_request("Reply with the single word ready.",{},"",qwen)
	check(not reply.error.is_empty() and reply.response.is_empty(),"local requests are denied until the user grants local transmission consent")
	reply.error="";client.policy.local_enabled=true
	client.send_request("Reply with the single word ready.",{},"",qwen)
	started=Time.get_ticks_msec()
	while client._is_busy and Time.get_ticks_msec()-started<100000:await process_frame
	print("QWEN RESPONSE ",reply.response," ERROR ",reply.error)
	check(not reply.response.strip_edges().is_empty() and reply.error.is_empty(),"real bundled Qwen inference completes through the existing GDScript LLM adapter")
	client.free();runtime.stop()
	check(not runtime.is_running(),"stopping Cortex releases only its owned inference process")
	runtime.free()
	print("CORTEX LOCAL COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
