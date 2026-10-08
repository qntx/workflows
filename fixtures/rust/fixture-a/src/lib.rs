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

/// Marker present only when `extra` is off.
#[cfg(not(feature = "extra"))]
#[must_use]
pub fn minimal() -> &'static str {
    "minimal"
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

    // fixture-b depends on fixture-a with default features, so a
    // workspace-wide `cargo test --workspace --no-default-features` still
    // unifies `extra` into this crate and this test is silently skipped —
    // the feature-unification masking that the `packages` input exists to
    // avoid. It only actually runs under `cargo test -p fixture-a
    // --no-default-features` (the e2e-rust-packages job in self-ci.yml).
    #[cfg(not(feature = "extra"))]
    #[test]
    fn minimal_build_has_no_extra() {
        assert_eq!(minimal(), "minimal");
    }
}
