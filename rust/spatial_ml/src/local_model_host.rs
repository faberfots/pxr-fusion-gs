//! Owns the process handle, so shutdown can never target an unrelated reused PID.
use godot::prelude::*;
use std::{path::Path, process::{Child,Command,Stdio}};
#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct CortexLocalModelHost {child:Option<Child>,error:String,base:Base<RefCounted>}
#[godot_api] impl IRefCounted for CortexLocalModelHost {
    fn init(base:Base<RefCounted>)->Self{Self{child:None,error:String::new(),base}}
}
impl CortexLocalModelHost {
    fn terminate(&mut self) {if let Some(mut child)=self.child.take(){let _=child.kill();let _=child.wait();}}
}
impl Drop for CortexLocalModelHost {fn drop(&mut self){self.terminate();}}
#[godot_api] impl CortexLocalModelHost {
    #[func] fn start(&mut self,executable:GString,model:GString)->bool {
        self.terminate();
        let executable=executable.to_string();let model=model.to_string();
        if !Path::new(&executable).is_absolute() || !Path::new(&executable).is_file() || !Path::new(&model).is_absolute() || !Path::new(&model).is_file() {self.error="Verified local executable and model paths are required.".into();return false;}
        let mut command=Command::new(&executable);
        command.current_dir(Path::new(&executable).parent().unwrap()).args(["--model",&model,"--host","127.0.0.1","--port","18081","--alias","qwen-local","--ctx-size","2048","--parallel","1","--threads","4","--n-gpu-layers","0","--no-webui"]).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
        #[cfg(windows)] {use std::os::windows::process::CommandExt;command.creation_flags(0x08000000);}
        match command.spawn(){Ok(child)=>{self.child=Some(child);self.error.clear();true},Err(_)=>{self.error="The bundled local runtime could not start.".into();false}}
    }
    #[func] fn is_running(&mut self)->bool {
        let Some(child)=self.child.as_mut() else{return false;};
        match child.try_wait(){Ok(None)=>true,_=>{self.child=None;false}}
    }
    #[func] fn stop(&mut self){self.terminate();}
    #[func] fn get_last_error(&self)->GString{GString::from(self.error.as_str())}
}
