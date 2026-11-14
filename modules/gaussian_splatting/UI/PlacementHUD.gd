extends Control
## Scene-authored placement controls; preview reads the viewer's pending Node3D.
var viewer:GaussianSplattingViewer
var _state:Dictionary={}
func _ready()->void:
	GSUiScale.apply(%Panel)
	%ImportKind.item_selected.connect(func(index):viewer.set_placement_kind(index))
	%Anchor.item_selected.connect(func(index):viewer.set_placement_anchor(index))
	%Place.pressed.connect(func():viewer.request_model_placement())
	%Original.pressed.connect(func():viewer.confirm_model_placement(true))
	%Cancel.pressed.connect(func():viewer.cancel_model_placement())
	visible=false
func _process(_delta:float)->void:
	_state=viewer.get_placement_state() if is_instance_valid(viewer) else {}
	visible=not _state.is_empty()
	if not visible:return
	var environment:bool=_state.kind==GaussianSplat.ImportKind.ENVIRONMENT
	%ImportKind.select(_state.kind)
	%Anchor.visible=not environment
	%Place.visible=not environment
	%Original.visible=not environment
	%Title.text="PLACE · "+str(_state.name)
	%Status.text=("Loading environment at its source pose…" if environment else str(_state.status))+("\n"+str(_state.surface) if _state.valid else "")
	%Place.disabled=not _state.ready or not _state.valid
	%Original.disabled=not _state.ready
	%Anchor.select(_state.anchor)
	%Panel.reset_size()
	var extent:=GSUiScale.extent(%Panel)
	var position_hint:=Vector2(maxf(12,(get_viewport_rect().size.x-extent.x)*0.5),24)
	var camera:=viewer.get_camera()
	if _state.valid and camera and not camera.is_position_behind(_state.target):
		if Rect2(position_hint,extent).has_point(camera.unproject_position(_state.target)):
			position_hint.y=maxf(12,get_viewport_rect().size.y-extent.y-42)
	%Panel.position=position_hint
	queue_redraw()
func _draw()->void:
	if _state.is_empty() or not _state.valid:return
	var camera:=viewer.get_camera()
	var point:Vector3=_state.target
	if not camera or camera.is_position_behind(point):return
	var pixel:=camera.unproject_position(point)
	var radius:=12*GSUiScale.FACTOR
	draw_circle(pixel,radius+2,Color(0.02,0.03,0.04,0.8),true,-1,true)
	draw_arc(pixel,radius,0,TAU,40,Color("ef4444"),2,true)
	draw_line(pixel-Vector2(18,0)*GSUiScale.FACTOR,pixel+Vector2(18,0)*GSUiScale.FACTOR,Color.WHITE,1,true)
	draw_line(pixel-Vector2(0,18)*GSUiScale.FACTOR,pixel+Vector2(0,18)*GSUiScale.FACTOR,Color.WHITE,1,true)
	if not _state.ready:return
	var bounds:AABB=_state.bounds
	for index in range(8):
		for axis in [1,2,4]:
			var other:int=index^axis
			if other<index:continue
			var first:=bounds.get_endpoint(index);var second:=bounds.get_endpoint(other)
			if camera.is_position_behind(first) or camera.is_position_behind(second):continue
			var a:=camera.unproject_position(first);var b:=camera.unproject_position(second)
			draw_line(a,b,Color(0.03,0.03,0.04,0.7),3,true)
			draw_line(a,b,Color(1,0.4,0.4,0.9),1,true)
