//! Fixture cdylib for ci-wasm e2e tests. Plain extern exports, no wasm-bindgen.

unsafe extern "C" {
    fn fixture_add(a: i32, b: i32) -> i32;
}

/// Adds two numbers via the cc-compiled helper.
#[unsafe(no_mangle)]
pub extern "C" fn add(a: i32, b: i32) -> i32 {
    unsafe { fixture_add(a, b) }
}
