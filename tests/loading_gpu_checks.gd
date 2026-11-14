extends SceneTree
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func run()->void:
	var count:=513
	var mapping:Dictionary={"x":0,"y":1,"z":2,"sx":55,"sy":56,"sz":57,"rw":58,"rx":59,"ry":60,"rz":61,"opacity":54,"dc":[6,7,8],"rgb":[-1,-1,-1],"rgb_divisors":[1.0,1.0,1.0],"rest":[]}
	for i in range(45):mapping.rest.append(9+i)
	var values:=PackedFloat32Array();values.resize(count*62)
	for i in range(count):
		var v:=i*62;values[v]=i*0.01;values[v+1]=sin(i*0.2);values[v+2]=cos(i*0.3)
		values[v+6]=0.1;values[v+7]=-0.2;values[v+8]=0.3
		for j in range(45):values[v+9+j]=sin(j*0.21+i)*0.05
		values[v+54]=float(i%11)-5;values[v+55]=-4;values[v+56]=-8;values[v+57]=-25
		var q:=Quaternion.from_euler(Vector3(i*0.02,0.3,-0.15))
		values[v+58]=q.w*2;values[v+59]=q.x*2;values[v+60]=q.y*2;values[v+61]=q.z*2
	var cpu:=PlyFile.validated_pack(values,62,mapping,7,1.5)
	var decoder:=GSGpuDecoder.new()
	check(decoder.initialize(count,62,mapping),"worker-local GLSL decoder initializes with bounded buffers")
	if not decoder.device:quit(1);return
	var result:=decoder.convert(values,count,7,1.5,2)
	check(not result.has("error"),"GLSL converts all finite degree-three Gaussians")
	if result.has("error"):decoder.cleanup();quit(1);return
	var expected:PackedFloat32Array=cpu.data.to_float32_array();var actual:PackedFloat32Array=result.data.to_float32_array()
	var drift:=0.0;var same:=expected.size()==actual.size()
	for i in range(expected.size()):
		drift=maxf(drift,absf(expected[i]-actual[i]));same=same and absf(expected[i]-actual[i])<=maxf(0.000002,absf(expected[i])*0.00003)
	print("GLSL NUMERIC MAX ABS ERROR ",drift)
	check(same,"all 60 fields match the GDScript reference within declared float32 tolerance")
	var verified:=true
	var data:PackedByteArray=result.data;var hashes:PackedByteArray=result.cache_leaf_hashes
	for leaf in range(ceili(data.size()/float(GSPreparedCache.LEAF_BYTES))):
		verified=verified and GSPreparedCache.digest(data.slice(leaf*GSPreparedCache.LEAF_BYTES,mini(data.size(),(leaf+1)*GSPreparedCache.LEAF_BYTES)))==hashes.slice(leaf*32,(leaf+1)*32).hex_encode()
	check(verified,"GLSL SHA-256 leaves match Godot HashingContext byte for byte")
	check(result.aabb.is_equal_approx(cpu.aabb),"GLSL reduction preserves full bounds including padded workgroups")
	values[58]=0;values[59]=0;values[60]=0;values[61]=0
	check(decoder.convert(values,count,7,1.5).has("error"),"GPU rejects zero quaternions before a model can commit")
	values[58]=1;values[10]=NAN
	check(decoder.convert(values,count,7,1.5).has("error"),"GPU validates every source property, including SH values")
	decoder.cleanup()
	check(decoder.initialize(count,60,{},true),"prepared-data validation shares the bounded GLSL backend")
	result=decoder.convert(expected,count,9,2.0)
	actual=result.data.to_float32_array();same=true
	for i in range(count):
		for j in range(60):
			var index:=i*60+j
			var target:=9.0 if j==11 else (2.0 if j==3 else expected[index])
			same=same and actual[index]==target
	check(same,"prepared data preserves every stored bit except the required runtime identity/time fields")
	expected[10]=2
	check(decoder.convert(expected,count,9,2).has("error"),"prepared opacity outside zero-to-one is rejected")
	decoder.cleanup()
	print("LOADING GPU COMPLETE: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
