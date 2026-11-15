use godot::prelude::*;
use unicode_normalization::UnicodeNormalization;
#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct CortexTextTools { base:Base<RefCounted> }
#[godot_api] impl IRefCounted for CortexTextTools {fn init(base:Base<RefCounted>)->Self{Self{base}}}
#[godot_api] impl CortexTextTools {
    #[func] fn normalize_clip(&self,text:GString)->GString {
        let raw=text.to_string();
        let first=html_escape::decode_html_entities(&raw);
        let second=html_escape::decode_html_entities(&first);
        GString::from(second.nfc().collect::<String>().trim().to_lowercase().as_str())
    }
}
