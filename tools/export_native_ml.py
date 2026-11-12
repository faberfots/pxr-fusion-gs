from pathlib import Path
import sys,torch,json,hashlib,time
import argparse
parser=argparse.ArgumentParser()
parser.add_argument('--source',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
root=args.source
sys.path.insert(0,str(root))
from mobile_sam import sam_model_registry
from mobile_sam.utils.onnx import SamOnnxModel
torch.set_num_threads(4)
model=sam_model_registry['vit_t'](checkpoint=None)
state=torch.load(root/'weights/mobile_sam.pt',map_location='cpu',weights_only=True)
model.load_state_dict(state);model.eval()
out=args.output;out.mkdir(parents=True,exist_ok=True)
with torch.no_grad():
 print('EXPORT ENCODER',flush=True)
 torch.onnx.export(model.image_encoder,torch.zeros(1,3,1024,1024),str(out/'mobile_sam_encoder.onnx'),input_names=['image'],output_names=['image_embeddings'],opset_version=17,do_constant_folding=True)
 print('EXPORT DECODER',flush=True)
 decoder=SamOnnxModel(model,return_single_mask=False).eval()
 args=(torch.zeros(1,256,64,64),torch.tensor([[[400.,400.],[0.,0.]]]),torch.tensor([[1.,-1.]]),torch.zeros(1,1,256,256),torch.zeros(1),torch.tensor([512.,512.]))
 torch.onnx.export(decoder,args,str(out/'mobile_sam_decoder.onnx'),input_names=['image_embeddings','point_coords','point_labels','mask_input','has_mask_input','orig_im_size'],output_names=['masks','iou_predictions','low_res_masks'],dynamic_axes={'point_coords':{1:'num_points'},'point_labels':{1:'num_points'}},opset_version=17,do_constant_folding=True)
print('EXPORT COMPLETE',flush=True)
