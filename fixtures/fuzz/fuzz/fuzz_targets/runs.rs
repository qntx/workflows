#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let needle = fixture_fuzz::first_byte(data);
    let _ = fixture_fuzz::longest_run(data, needle);
});
