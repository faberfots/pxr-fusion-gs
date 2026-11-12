extends SceneTree
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func run()->void:
	var args:=OS.get_cmdline_user_args()
	check(NativeMLBridge.availability().available,"verified native delivery reports available")
	var segmenter:Object=NativeMLBridge.load_default_segmenter()
	check(segmenter!=null and segmenter.call("is_ready"),"packaged MobileSAM models and verified CPU runtime initialize through GDScript")
	if not segmenter:quit(1);return
	var image:Image
	if not args.is_empty():image=Image.load_from_file(args[0])
	else:
		image=Image.create(640,384,false,Image.FORMAT_RGB8)
		image.fill(Color8(235,235,235))
		for y in range(384):
			for x in range(640):
				var radius:=pow((x-180.0)/110.0,2)+pow((y-190.0)/120.0,2)
				if radius<=1.0:image.set_pixel(x,y,Color8(200,35,30) if radius<0.92 else Color8(80,10,10))
				elif x>=380 and x<=560 and y>=90 and y<=290:image.set_pixel(x,y,Color8(25,150,70))
		image.save_png("user://native-test-input.png")
	image.convert(Image.FORMAT_RGB8)
	check(segmenter.call("encode_image",image),"actual RGB image encodes through Godot native bridge")
	var mask:PackedByteArray=segmenter.call("segment_with_points",PackedVector2Array([Vector2(180,190)]),PackedInt32Array([1]))
	check(segmenter.call("get_mask_size")==Vector2i(640,384) and mask.size()==640*384,"native decoder restores the original non-square image dimensions")
	var intersection:=0;var union_count:=0
	for y in range(384):
		for x in range(640):
			var expected:=pow((x-180.0)/110.0,2)+pow((y-190.0)/120.0,2)<=1.0
			var actual:=mask[y*640+x]>0
			if expected and actual:intersection+=1
			if expected or actual:union_count+=1
	var iou:=float(intersection)/maxi(1,union_count)
	print("NATIVE CIRCLE IOU ",iou)
	check(iou>.95,"native image segmentation matches the deterministic fixture mask")
	var other:PackedByteArray=segmenter.call("segment_with_points",PackedVector2Array([Vector2(470,170)]),PackedInt32Array([1]))
	check(other!=mask and other[170*640+470]>0 and other[190*640+180]==0,"native prompts select different actual image objects")
	var display:=mask.duplicate()
	for i in range(display.size()):display[i]*=255
	Image.create_from_data(640,384,false,Image.FORMAT_L8,display).save_png("user://native-circle-mask.png")
	print("NATIVE INFERENCE COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
