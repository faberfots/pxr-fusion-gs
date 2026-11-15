class_name CortexPresets
extends RefCounted
## One catalog owns user goals, request defaults and their plain-language help.
const DEFAULT="pick"
const ORDER=["pick","find","scene","selection","connected","custom"]
const PROGRESS={"Queued":"Preparing your search…","Verifying local artifacts":"Checking the included files…","Initializing SAM3 CPU sessions":"Loading the local selection tool…","Encoding captured image on CPU":"Reading your captured picture…","Decoding segmentation prompt":"Finding the object you asked for…","Preparing mask preview":"Highlighting the results…","Idle":"Ready for your next search."}
const DEFINITIONS={
	"pick":{
		"title":"Select with a click · recommended","kind":"segment","engine":"mobile_sam",
		"summary":"Click an object in a captured view to find and select its imported 3D GS model.",
		"steps":"1. Capture your view.\n2. Click the object in the picture, then Find object.\n3. Check the highlighted area, then Select model.",
		"privacy":"Private · no account or cloud upload. Uses the smaller local model (MobileSAM), which loads when you search.",
		"limit":"Selects an entire imported model. Individual objects inside one large scan are not separated into new models."
	},
	"find":{
		"title":"Find by description","kind":"segment","engine":"sam3",
		"summary":"Type what you want to find, such as person or motorcycle, in a captured view.",
		"steps":"1. Capture your view.\n2. Type a short description; you can also draw a box around the area.\n3. Find object, check a result, then Select model.",
		"privacy":"Private · no account or cloud upload. Uses the larger local model (SAM3); the first search takes longer.",
		"limit":"Finds visible areas in the picture and selects an existing imported model. It does not cut objects out of a scan."
	},
	"scene":{
		"title":"Understand my scene · private","kind":"private","scope":"visible",
		"summary":"Ask the private assistant about the names, positions and layout of your visible models.",
		"steps":"1. Type your question, or try the example.\n2. Start & ask privately loads the included assistant for you.\n3. Read its explanation; your scene stays under your control.",
		"privacy":"Runs on this computer using Qwen. Shares scene information locally, without an image or cloud account. Starts only when you ask.",
		"limit":"This assistant reads scene information; it cannot see the picture or move your models. Names and explanations can be imperfect.",
		"example":"Explain the layout of my visible models and suggest how I could arrange them.",
		"placeholder":"What would you like to understand about your scene?"
	},
	"selection":{
		"title":"Explain my selected model · private","kind":"private","scope":"selected",
		"summary":"Ask about the imported model you have selected, using its name and scene information.",
		"steps":"1. Select a model in the scene or Scene navigator.\n2. Ask a question, or try the example.\n3. Start & ask privately loads the included assistant if needed.",
		"privacy":"Runs on this computer using Qwen. Only selected-model scene information is included; no image or cloud upload.",
		"limit":"Select a model first. The assistant cannot identify its appearance from scene information alone and does not edit it.",
		"example":"Explain the selected model's position, size and relationship to the scene.",
		"placeholder":"What would you like to know about the selected model?"
	},
	"connected":{
		"title":"Ask my connected assistant","kind":"connected",
		"summary":"Use the assistant you choose below. A configured vision model can also discuss a shared picture.",
		"steps":"1. Choose your saved connection below. Advanced settings can connect an account once.\n2. Review what will be shared and enable that destination.\n3. Ask your question. Picture sharing follows your connection settings.",
		"privacy":"A remote provider may receive your question, scene details and an enabled picture, and may charge usage fees. Nothing is sent before you ask.",
		"limit":"Requires a configured model and any required account key. This preset explains; it does not grant camera or model commands.",
		"example":"Describe what you can determine from the information I have shared.",
		"placeholder":"Ask your chosen assistant…"
	},
	"custom":{
		"title":"Advanced / my own settings","kind":"custom",
		"summary":"Keep full control of connections, local models, sharing and optional scene commands.",
		"steps":"Ask sends your configured input. Select uses your saved local model settings. Setup edits connections, vision, privacy and diagnostics.",
		"privacy":"Your existing settings are preserved. Transmission and scene commands still require their own permission.",
		"limit":"Use a guided preset above whenever you want a simpler workflow."
	}
}
static func definition(id:String)->Dictionary:return DEFINITIONS.get(id,DEFINITIONS[DEFAULT]).duplicate(true)
static func kind(id:String)->String:return definition(id).kind
static func progress_label(phase:String)->String:return PROGRESS.get(phase,phase)
static func help_text(id:String)->String:
	var item:=definition(id)
	return item.steps+"\n\n"+item.privacy+"\n\n"+item.limit
