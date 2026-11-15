//! Separate SAM3 ONNX contract. CPU sessions and embeddings belong to one worker.
use godot::{prelude::*, classes::Image};
use image::{RgbImage, imageops::FilterType};
use ort::{session::Session, value::Tensor};
use std::path::Path;

struct Features {
    position:Tensor<f32>, fpn0:Tensor<f32>, fpn1:Tensor<f32>, fpn2:Tensor<f32>,
}
struct Language { mask:Tensor<bool>, features:Tensor<f32>, tokens:Vec<i64> }
#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct Sam3Segmenter {
    encoder:Option<Session>, language:Option<Session>, decoder:Option<Session>,
    features:Option<Features>, text:Option<Language>, original:(usize,usize), error:String,
    base:Base<RefCounted>,
}
#[godot_api]
impl IRefCounted for Sam3Segmenter {
    fn init(base:Base<RefCounted>)->Self {
        Self { encoder:None,language:None,decoder:None,features:None,text:None,original:(0,0),error:String::new(),base }
    }
}
fn session(path:&Path)->ort::Result<Session> {
    Session::builder()?.with_intra_threads(4)?.with_inter_threads(1)?.commit_from_file(path)
}
fn float_tensor(outputs:&ort::session::SessionOutputs<'_>,name:&str,expected:&[i64])->Result<Tensor<f32>,String> {
    let value=outputs.get(name).ok_or_else(||format!("Missing tensor {name}"))?;
    let (shape,values)=value.try_extract_tensor::<f32>().map_err(|e|e.to_string())?;
    if shape.as_ref()!=expected || values.iter().any(|x|!x.is_finite()) { return Err(format!("Invalid tensor {name}")); }
    Tensor::from_array((expected.iter().map(|v|*v as usize).collect::<Vec<_>>(),values.to_vec())).map_err(|e|e.to_string())
}
#[godot_api]
impl Sam3Segmenter {
    #[func] fn load_model_with_runtime(&mut self,directory:GString,runtime:GString)->bool {
        self.encoder=None;self.language=None;self.decoder=None;self.features=None;self.text=None;
        let result=(||->Result<(),String>{
            let directory=directory.to_string();let root=Path::new(&directory);let runtime=runtime.to_string();
            if !root.is_absolute() || !Path::new(&runtime).is_absolute() { return Err("Use verified absolute model/runtime paths.".into()); }
            crate::runtime_loader::initialize(&runtime)?;
            let encoder=session(&root.join("sam3_image_encoder.onnx")).map_err(|e|e.to_string())?;
            let language=session(&root.join("sam3_language_encoder.onnx")).map_err(|e|e.to_string())?;
            let decoder=session(&root.join("sam3_decoder.onnx")).map_err(|e|e.to_string())?;
            let names:Vec<_>=decoder.inputs().iter().map(|i|i.name()).collect();
            let expected=["original_height","original_width","vision_pos_enc_2","backbone_fpn_0","backbone_fpn_1","backbone_fpn_2","language_mask","language_features","box_coords","box_labels","box_masks"];
            if encoder.inputs().len()!=1 || encoder.inputs()[0].name()!="image" || language.inputs().len()!=1 || language.inputs()[0].name()!="tokens" || names.len()!=expected.len() || expected.iter().any(|n|!names.contains(n)) { return Err("Unsupported SAM3 tensor contract.".into()); }
            self.encoder=Some(encoder);self.language=Some(language);self.decoder=Some(decoder);Ok(())
        })();
        match result {Ok(())=>{self.error.clear();true},Err(error)=>{self.error=error;false}}
    }
    #[func] fn is_ready(&self)->bool {self.encoder.is_some()&&self.language.is_some()&&self.decoder.is_some()}
    #[func] fn get_last_error(&self)->GString { GString::from(self.error.as_str()) }
    #[func] fn encode_image(&mut self,image:Gd<Image>)->bool {
        self.features=None;
        let result=(||->Result<Features,String>{
            let (w,h)=(image.get_width() as usize,image.get_height() as usize);
            if image.is_compressed() || w==0 || h==0 || w.checked_mul(h).is_none_or(|n|n>2_000_000) {return Err("Use an uncompressed image of at most two million pixels.".into());}
            let bytes=image.get_data();
            let rgb=match image.get_format() {
                godot::classes::image::Format::RGB8=>bytes.as_slice().to_vec(),
                godot::classes::image::Format::RGBA8=>bytes.as_slice().chunks_exact(4).flat_map(|p|[p[0],p[1],p[2]]).collect(),
                _=>return Err("Use RGB8 or RGBA8 image data.".into())
            };
            let original=RgbImage::from_raw(w as u32,h as u32,rgb).ok_or("Invalid RGB image")?;
            let resized=image::imageops::resize(&original,1008,1008,FilterType::Triangle);
            let mut chw=vec![0u8;3*1008*1008];
            for y in 0..1008 {for x in 0..1008 {let p=resized.get_pixel(x,y).0;for c in 0..3 {chw[c*1008*1008+y as usize*1008+x as usize]=p[c];}}}
            let tensor=Tensor::from_array(([3usize,1008,1008],chw)).map_err(|e|e.to_string())?;
            let encoder=self.encoder.as_mut().ok_or("SAM3 encoder is not ready")?;
            let outputs=encoder.run(ort::inputs!["image"=>tensor]).map_err(|e|e.to_string())?;
            let result=Features {position:float_tensor(&outputs,"vision_pos_enc_2",&[1,256,72,72])?,fpn0:float_tensor(&outputs,"backbone_fpn_0",&[1,256,288,288])?,fpn1:float_tensor(&outputs,"backbone_fpn_1",&[1,256,144,144])?,fpn2:float_tensor(&outputs,"backbone_fpn_2",&[1,256,72,72])?};
            self.original=(w,h);Ok(result)
        })();
        match result {Ok(features)=>{self.features=Some(features);self.error.clear();true},Err(error)=>{self.error=error;false}}
    }
    #[func] fn segment_with_tokens(&mut self,tokens:PackedInt64Array,rectangle:Rect2,has_box:bool,threshold:f64)->VarDictionary {
        let result=self.decode(tokens.as_slice(),rectangle,has_box,threshold);
        match result {Ok(value)=>{self.error.clear();value},Err(error)=>{self.error=error;let mut value=VarDictionary::new();value.set("error",GString::from(self.error.as_str()));value}}
    }
}
impl Sam3Segmenter {
    fn decode(&mut self,tokens:&[i64],rectangle:Rect2,has_box:bool,threshold:f64)->Result<VarDictionary,String> {
        if tokens.len()!=32 || tokens[0]!=49406 || tokens.iter().any(|v|*v<0||*v>49407) || !threshold.is_finite() || !(0.0..=1.0).contains(&threshold) {return Err("Invalid CLIP prompt tokens or confidence threshold.".into());}
        let (w,h)=self.original;
        if has_box && (!rectangle.position.is_finite()||!rectangle.size.is_finite()||rectangle.position.x<0.0||rectangle.position.y<0.0||rectangle.size.x<=0.0||rectangle.size.y<=0.0||rectangle.end().x>w as f32||rectangle.end().y>h as f32) {return Err("Box must be inside the captured image.".into());}
        if self.text.as_ref().is_none_or(|l|l.tokens!=tokens) {
            let input=Tensor::from_array(([1usize,32],tokens.to_vec())).map_err(|e|e.to_string())?;
            let language=self.language.as_mut().ok_or("Language encoder is not ready")?;
            let outputs=language.run(ort::inputs!["tokens"=>input]).map_err(|e|e.to_string())?;
            let (shape,mask)=outputs.get("text_attention_mask").ok_or("Missing language mask")?.try_extract_tensor::<bool>().map_err(|e|e.to_string())?;
            if shape.as_ref()!=[1,32] {return Err("Invalid language mask shape".into());}
            self.text=Some(Language {mask:Tensor::from_array(([1usize,32],mask.to_vec())).map_err(|e|e.to_string())?,features:float_tensor(&outputs,"text_memory",&[32,1,256])?,tokens:tokens.to_vec()});
        }
        let vision=self.features.as_ref().ok_or("Capture and encode an image first")?;
        let language=self.text.as_ref().ok_or("Language features are unavailable")?;
        let coordinates=if has_box {vec![(rectangle.position.x+rectangle.size.x*0.5)/w as f32,(rectangle.position.y+rectangle.size.y*0.5)/h as f32,rectangle.size.x/w as f32,rectangle.size.y/h as f32]} else {vec![0.0;4]};
        let height=Tensor::from_array((Vec::<usize>::new(),vec![h as i64])).map_err(|e|e.to_string())?;
        let width=Tensor::from_array((Vec::<usize>::new(),vec![w as i64])).map_err(|e|e.to_string())?;
        let coords=Tensor::from_array(([1usize,1,4],coordinates)).map_err(|e|e.to_string())?;
        let labels=Tensor::from_array(([1usize,1],vec![1i64])).map_err(|e|e.to_string())?;
        let box_mask=Tensor::from_array(([1usize,1],vec![!has_box])).map_err(|e|e.to_string())?;
        let decoder=self.decoder.as_mut().ok_or("SAM3 decoder is not ready")?;
        let outputs=decoder.run(ort::inputs!["original_height"=>height,"original_width"=>width,"vision_pos_enc_2"=>&vision.position,"backbone_fpn_0"=>&vision.fpn0,"backbone_fpn_1"=>&vision.fpn1,"backbone_fpn_2"=>&vision.fpn2,"language_mask"=>&language.mask,"language_features"=>&language.features,"box_coords"=>coords,"box_labels"=>labels,"box_masks"=>box_mask]).map_err(|e|e.to_string())?;
        let (shape,masks)=outputs.get("masks").ok_or("Missing SAM3 masks")?.try_extract_tensor::<bool>().map_err(|e|e.to_string())?;
        let (_,scores)=outputs.get("scores").ok_or("Missing SAM3 scores")?.try_extract_tensor::<f32>().map_err(|e|e.to_string())?;
        if shape.len()!=4 || shape[0]<0 || shape[0]>512 || shape[1]!=1 || shape[2]!=h as i64 || shape[3]!=w as i64 || scores.len()!=shape[0] as usize || masks.len()!=scores.len()*w*h || scores.iter().any(|v|!v.is_finite()) {return Err("Invalid SAM3 result dimensions".into());}
        let mut indices:Vec<usize>=(0..scores.len()).filter(|i|scores[*i] as f64>=threshold).collect();
        indices.sort_by(|a,b|scores[*b].total_cmp(&scores[*a]));indices.truncate(8);
        let mut result_masks=Array::<PackedByteArray>::new();let mut result_scores=PackedFloat32Array::new();
        for index in indices {let mask:Vec<u8>=masks[index*w*h..(index+1)*w*h].iter().map(|v|u8::from(*v)).collect();result_masks.push(&PackedByteArray::from(mask.as_slice()));result_scores.push(scores[index]);}
        let mut result=VarDictionary::new();result.set("masks",result_masks);result.set("scores",result_scores);result.set("size",Vector2i::new(w as i32,h as i32));Ok(result)
    }
}
