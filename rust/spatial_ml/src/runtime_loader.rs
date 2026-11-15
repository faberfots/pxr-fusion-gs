//! Resolve ORT's app-local C++ dependencies without changing PATH or DLL search state.
pub fn initialize(path: &str) -> Result<(), String> {
    #[cfg(windows)]
    let handle = {
        use std::ffi::c_void;
        #[link(name = "kernel32")]
        unsafe extern "system" {
            fn LoadLibraryExW(path: *const u16, file: *mut c_void, flags: u32) -> *mut c_void;
        }
        let name: Vec<u16> = path.encode_utf16().chain(Some(0)).collect();
        // Search this verified runtime's directory and normal safe Windows locations.
        let handle = unsafe { LoadLibraryExW(name.as_ptr(), std::ptr::null_mut(), 0x100 | 0x1000) };
        if handle.is_null() { return Err("Verified ONNX Runtime or its local C++ dependencies could not load.".into()); }
        handle
    };
    let result = ort::init_from(path)
        .map(|builder| { builder.with_telemetry(false).commit(); })
        .map_err(|_| "ONNX Runtime initialization failed.".to_string());
    #[cfg(windows)]
    {
        use std::ffi::c_void;
        #[link(name = "kernel32")]
        unsafe extern "system" { fn FreeLibrary(module: *mut c_void) -> i32; }
        // ort retains its own libloading handle; release only our temporary preload.
        unsafe { FreeLibrary(handle); }
    }
    result
}
