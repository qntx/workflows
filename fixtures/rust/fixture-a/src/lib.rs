//! Fixture crate A for qntx/workflows end-to-end tests.

/// Adds one to the input.
#[must_use]
pub fn inc(x: u64) -> u64 {
    x + 1
}

/// Returns the greeting behind the `extra` feature.
#[cfg(feature = "extra")]
#[must_use]
pub fn extra() -> &'static str {
    "extra"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn inc_adds_one() {
        assert_eq!(inc(41), 42);
    }

    #[cfg(feature = "extra")]
    #[test]
    fn extra_is_stable() {
        assert_eq!(extra(), "extra");
    }
}
