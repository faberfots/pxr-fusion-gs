//! Windows user credential storage. No secret file, shell command or environment mutation.
use godot::prelude::*;

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct CortexCredentialVault { base: Base<RefCounted> }
#[godot_api]
impl IRefCounted for CortexCredentialVault {
    fn init(base: Base<RefCounted>) -> Self { Self { base } }
}
fn target(slot: &str) -> Option<Vec<u16>> {
    if slot.is_empty() || slot.len()>120 || !slot.bytes().all(|b| b.is_ascii_alphanumeric() || b==b'_' || b==b'-') { return None; }
    Some(format!("Polygonics/PXRFusion/Cortex/{slot}").encode_utf16().chain(Some(0)).collect())
}
#[cfg(windows)]
mod platform {
    use super::target;
    use std::{ffi::c_void, ptr};
    #[repr(C)] struct FileTime { low:u32, high:u32 }
    #[repr(C)] struct Credential {
        flags:u32, kind:u32, target:*mut u16, comment:*mut u16, written:FileTime,
        size:u32, blob:*mut u8, persist:u32, attributes_count:u32, attributes:*mut c_void,
        alias:*mut u16, username:*mut u16,
    }
    #[link(name="advapi32")]
    unsafe extern "system" {
        fn CredWriteW(credential:*const Credential,flags:u32)->i32;
        fn CredReadW(target:*const u16,kind:u32,flags:u32,credential:*mut *mut Credential)->i32;
        fn CredDeleteW(target:*const u16,kind:u32,flags:u32)->i32;
        fn CredFree(buffer:*mut c_void);
    }
    pub fn write(slot:&str, secret:&str)->bool {
        let Some(mut name)=target(slot) else { return false; };
        if secret.is_empty() || secret.len()>2560 || secret.bytes().any(|b| b==0 || b==10 || b==13) { return false; }
        let mut bytes=secret.as_bytes().to_vec();
        let mut user:Vec<u16>="PXRFusion".encode_utf16().chain(Some(0)).collect();
        let item=Credential { flags:0,kind:1,target:name.as_mut_ptr(),comment:ptr::null_mut(),written:FileTime{low:0,high:0},size:bytes.len() as u32,blob:bytes.as_mut_ptr(),persist:2,attributes_count:0,attributes:ptr::null_mut(),alias:ptr::null_mut(),username:user.as_mut_ptr() };
        let success=unsafe { CredWriteW(&item,0)!=0 };
        for byte in &mut bytes { unsafe { ptr::write_volatile(byte,0); } }
        success
    }
    pub fn read(slot:&str)->String {
        let Some(name)=target(slot) else { return String::new(); };
        let mut item:*mut Credential=ptr::null_mut();
        if unsafe { CredReadW(name.as_ptr(),1,0,&mut item)==0 } || item.is_null() { return String::new(); }
        let value=unsafe {
            if (*item).size>2560 || (*item).blob.is_null() { String::new() }
            else { String::from_utf8_lossy(std::slice::from_raw_parts((*item).blob,(*item).size as usize)).into_owned() }
        };
        unsafe { CredFree(item.cast()); }
        value
    }
    pub fn delete(slot:&str)->bool {
        let Some(name)=target(slot) else { return false; };
        unsafe { CredDeleteW(name.as_ptr(),1,0)!=0 }
    }
}
#[godot_api]
impl CortexCredentialVault {
    #[func] fn write_secret(&self, slot:GString, secret:GString)->bool {
        #[cfg(windows)] { platform::write(&slot.to_string(),&secret.to_string()) }
        #[cfg(not(windows))] { let _=(slot,secret);false }
    }
    #[func] fn read_secret(&self, slot:GString)->GString {
        #[cfg(windows)] { GString::from(platform::read(&slot.to_string()).as_str()) }
        #[cfg(not(windows))] { let _=slot;GString::new() }
    }
    #[func] fn delete_secret(&self, slot:GString)->bool {
        #[cfg(windows)] { platform::delete(&slot.to_string()) }
        #[cfg(not(windows))] { let _=slot;false }
    }
}
#[cfg(test)] mod tests {
    #[test] fn credential_namespace_is_bounded() {
        assert!(super::target("openai-123abc").is_some());
        assert!(super::target("../another-app").is_none());
        assert!(super::target("").is_none());
    }
}
