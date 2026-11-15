//! Explicit MobileSAM ONNX contract; CPU inference through a supplied ONNX Runtime.
use godot::prelude::*;
use godot::classes::Image;
use image::{imageops::FilterType, RgbImage};
use ort::{session::Session, value::Tensor};
use std::path::Path;

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct MobileSamSegmenter {
    encoder: Option<Session>,
    decoder: Option<Session>,
    embeddings: Option<Tensor<f32>>,
    original: (usize, usize),
    resized: (usize, usize),
    mask_size: Vector2i,
    base: Base<RefCounted>,
}
#[godot_api]
impl IRefCounted for MobileSamSegmenter {
    fn init(base: Base<RefCounted>) -> Self {
        Self { encoder: None, decoder: None, embeddings: None, original: (0,0), resized: (0,0), mask_size: Vector2i::ZERO, base }
    }
}
fn load_session(path: &str) -> ort::Result<Session> {
    Session::builder()?.commit_from_file(path)
}
/// RGB bytes -> aspect-preserving resize, normalized CHW and zero padding.
fn preprocess(rgb: &[u8], width: usize, height: usize) -> Option<(Vec<f32>, usize, usize)> {
    if width == 0 || height == 0 || width > 16384 || height > 16384 || rgb.len() != width.checked_mul(height)?.checked_mul(3)? { return None; }
    let image = RgbImage::from_raw(width as u32, height as u32, rgb.to_vec())?;
    let scale = 1024.0 / width.max(height) as f64;
    let w = ((width as f64 * scale) + 0.5).floor().max(1.0) as u32;
    let h = ((height as f64 * scale) + 0.5).floor().max(1.0) as u32;
    let resized = image::imageops::resize(&image, w, h, FilterType::Triangle);
    let mut values = vec![0.0_f32; 3*1024*1024];
    let mean = [123.675, 116.28, 103.53];
    let std = [58.395, 57.12, 57.375];
    for y in 0..h as usize {
        for x in 0..w as usize {
            let pixel = resized.get_pixel(x as u32,y as u32).0;
            for c in 0..3 { values[c*1024*1024+y*1024+x]=(pixel[c] as f32-mean[c])/std[c]; }
        }
    }
    Some((values,w as usize,h as usize))
}
#[godot_api]
impl MobileSamSegmenter {
    #[func]
    fn load_model(&mut self, encoder_path: GString, decoder_path: GString) -> bool {
        let runtime = match std::env::var("ORT_DYLIB_PATH") {
            Ok(path) => path,
            Err(_) => { godot_error!("Supply a verified ONNX Runtime through NativeMLBridge or ORT_DYLIB_PATH."); return false; }
        };
        self.load_model_with_runtime(encoder_path, decoder_path, GString::from(runtime.as_str()))
    }
    #[func]
    fn load_model_with_runtime(&mut self, encoder_path: GString, decoder_path: GString, runtime_path: GString) -> bool {
        self.encoder=None; self.decoder=None; self.embeddings=None;
        let paths=[encoder_path.to_string(),decoder_path.to_string()];
        let runtime=runtime_path.to_string();
        if paths.iter().chain(std::iter::once(&runtime)).any(|p| !Path::new(p).is_absolute() || !Path::new(p).is_file()) {
            godot_error!("Supply verified materialized absolute artifact paths."); return false;
        }
		if crate::runtime_loader::initialize(&runtime).is_err() {
            godot_error!("ONNX Runtime initialization failed.");return false;
        }
        let (encoder,decoder)=match (load_session(&paths[0]),load_session(&paths[1])) {
            (Ok(e),Ok(d)) => (e,d),
            _ => { godot_error!("MobileSAM model or ONNX Runtime could not be loaded."); return false; }
        };
        let encoder_inputs: Vec<_>=encoder.inputs().iter().map(|v| v.name()).collect();
        let mut decoder_inputs: Vec<_>=decoder.inputs().iter().map(|v| v.name()).collect();
        decoder_inputs.sort_unstable();
        let mut expected=vec!["image_embeddings","point_coords","point_labels","mask_input","has_mask_input","orig_im_size"];
        expected.sort_unstable();
        if encoder_inputs!=["image"] || decoder_inputs!=expected {
            godot_error!("Unsupported ONNX model input contract."); return false;
        }
        self.encoder=Some(encoder); self.decoder=Some(decoder); true
    }
    #[func]
    fn is_ready(&self) -> bool { self.encoder.is_some() && self.decoder.is_some() }
    #[func]
    fn encode_image(&mut self, image: Gd<Image>) -> bool {
        self.embeddings=None;
        let (width,height)=(image.get_width() as usize,image.get_height() as usize);
        if image.is_compressed() { godot_error!("Decompress image before inference.");return false; }
        let raw=image.get_data();
        let rgb=match image.get_format() {
            godot::classes::image::Format::RGB8 => raw.as_slice().to_vec(),
            godot::classes::image::Format::RGBA8 => raw.as_slice().chunks_exact(4).flat_map(|p| [p[0],p[1],p[2]]).collect(),
            _ => { godot_error!("Convert image to RGB8 or RGBA8 before inference.");return false; }
        };
        let Some((pixels,w,h))=preprocess(&rgb,width,height) else { return false; };
        let tensor=match Tensor::from_array(([1usize,3,1024,1024],pixels)) { Ok(t)=>t,Err(_)=>return false };
        let Some(encoder)=self.encoder.as_mut() else { return false; };
        let outputs=match encoder.run(ort::inputs!["image"=>tensor]) { Ok(o)=>o,Err(e)=>{godot_error!("Encoder failed: {e}");return false;} };
        let Some(value)=outputs.get("image_embeddings") else { return false; };
        let Ok((shape,values))=value.try_extract_tensor::<f32>() else { return false; };
        if shape.as_ref()!=[1,256,64,64] || values.iter().any(|v| !v.is_finite()) { godot_error!("Unsupported embedding shape or non-finite output.");return false; }
        self.embeddings=Tensor::from_array((vec![1usize,256,64,64],values.to_vec())).ok();
        self.original=(width,height);self.resized=(w,h);
        self.embeddings.is_some()
    }
    #[func]
    fn segment_with_points(&mut self, points: PackedVector2Array, labels: PackedInt32Array) -> PackedByteArray {
        self.mask_size=Vector2i::ZERO;
        match self.decode(&points,&labels) {
            Ok((mask,w,h))=>{self.mask_size=Vector2i::new(w as i32,h as i32);PackedByteArray::from(mask.as_slice())}
            Err(message)=>{godot_error!("MobileSAM: {message}");PackedByteArray::new()}
        }
    }
    #[func]
    fn get_mask_size(&self) -> Vector2i { self.mask_size }
    #[func]
    fn get_version(&self) -> GString { GString::from(format!("SpatialML {}; explicit MobileSAM ONNX contract", env!("CARGO_PKG_VERSION")).as_str()) }
}
impl MobileSamSegmenter {
    fn decode(&mut self, points: &PackedVector2Array, labels: &PackedInt32Array) -> Result<(Vec<u8>,usize,usize),String> {
        let fail=|e: ort::Error|e.to_string();
        let n=points.len();
        if n==0 || n>256 || labels.len()!=n { return Err("Provide 1..256 points and matching labels.".into()); }
        let mut coords=Vec::with_capacity((n+1)*2);
        let mut point_labels=Vec::with_capacity(n+1);
        for i in 0..n {
            let p=points.get(i).ok_or("Missing prompt point")?;
            let label=labels.get(i).ok_or("Missing prompt label")?;
            if !p.x.is_finite()||!p.y.is_finite()||p.x<0.0||p.y<0.0||p.x>=self.original.0 as f32||p.y>=self.original.1 as f32||!(label==0||label==1) { return Err("Invalid pixel coordinates or prompt label.".into()); }
            coords.extend([p.x*self.resized.0 as f32/self.original.0 as f32,p.y*self.resized.1 as f32/self.original.1 as f32]);
            point_labels.push(label as f32);
        }
        coords.extend([0.0,0.0]);point_labels.push(-1.0);
        let Some(decoder)=self.decoder.as_mut() else {return Err("Decoder not ready".into());};
        let Some(embeddings)=self.embeddings.as_ref() else {return Err("Encode an image first".into());};
        let coordinates=Tensor::from_array(([1usize,n+1,2],coords)).map_err(fail)?;
        let labels=Tensor::from_array(([1usize,n+1],point_labels)).map_err(fail)?;
        let mask=Tensor::from_array(([1usize,1,256,256],vec![0f32;256*256])).map_err(fail)?;
        let has_mask=Tensor::from_array(([1usize],vec![0f32])).map_err(fail)?;
        let size=Tensor::from_array(([2usize],vec![self.original.1 as f32,self.original.0 as f32])).map_err(fail)?;
        let outputs=decoder.run(ort::inputs!["image_embeddings"=>embeddings,"point_coords"=>coordinates,"point_labels"=>labels,"mask_input"=>mask,"has_mask_input"=>has_mask,"orig_im_size"=>size]).map_err(fail)?;
        let value=outputs.get("masks").ok_or("Missing masks")?;
        let (shape,values)=value.try_extract_tensor::<f32>().map_err(fail)?;
        if shape.len()!=4 || shape[0]!=1 || shape[1]<1 || shape[1]>4 || shape[2]!=self.original.1 as i64 || shape[3]!=self.original.0 as i64 {return Err("Unsupported mask shape".into());}
        let channels=shape[1] as usize;
        let (h,w)=(shape[2] as usize,shape[3] as usize);
        let pixels=w.checked_mul(h).filter(|n| *n<=67108864).ok_or("Mask too large")?;
        let mut best=0;
        if channels>1 {
            let (_,scores)=outputs.get("iou_predictions").ok_or("Missing mask scores")?.try_extract_tensor::<f32>().map_err(fail)?;
            if scores.len()!=channels || scores.iter().any(|s| !s.is_finite()) {return Err("Invalid mask scores".into());}
            for i in 1..channels {if scores[i]>scores[best] {best=i;}}
        }
        if values.len()!=pixels*channels || values.iter().any(|v| !v.is_finite()) {return Err("Invalid mask data".into());}
        Ok((values[best*pixels..(best+1)*pixels].iter().map(|v|u8::from(*v>0.0)).collect(),w,h))
    }
}
#[cfg(test)]
mod tests {
    use super::preprocess;
    #[test]
    fn pixels_change_tensor_and_padding_is_zero() {
        let black=preprocess(&vec![0;4*2*3],4,2).expect("valid image");
        let white=preprocess(&vec![255;4*2*3],4,2).expect("valid image");
        assert_eq!((black.1,black.2),(1024,512));
        assert_ne!(black.0[0],white.0[0]);
        assert_eq!(black.0[700*1024],0.0);
        assert!((black.0[0]-(-123.675/58.395)).abs()<1e-5);
    }
    #[test]
    fn malformed_image_rejected() {assert!(preprocess(&[1,2],1,1).is_none());}
}
