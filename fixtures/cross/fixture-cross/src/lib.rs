//! Fixture crate for ci-rust-cross e2e tests.

unsafe extern "C" {
    fn fixture_double(x: u32) -> u32;
}

/// Doubles the input via the cc-compiled helper.
#[must_use]
pub fn double(x: u32) -> u32 {
    unsafe { fixture_double(x) }
}

/// Formats the input as a decimal string via itoa.
#[cfg(feature = "itoa")]
#[must_use]
pub fn format_u64(x: u64) -> String {
    itoa::Buffer::new().format(x).to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn double_doubles() {
        assert_eq!(double(21), 42);
    }

    #[cfg(feature = "itoa")]
    #[test]
    fn format_u64_formats() {
        assert_eq!(format_u64(42), "42");
    }
}
