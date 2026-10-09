//! Fixture crate C for qntx/workflows end-to-end tests: two independent
//! non-default features that must each compile alone
//! (`cargo hack check --each-feature`).

/// Returns the marker behind the `alpha` feature.
#[cfg(feature = "alpha")]
#[must_use]
pub fn alpha() -> &'static str {
    "alpha"
}

/// Returns the marker behind the `beta` feature.
#[cfg(feature = "beta")]
#[must_use]
pub fn beta() -> &'static str {
    "beta"
}

#[cfg(test)]
mod tests {
    #[cfg(feature = "alpha")]
    #[test]
    fn alpha_is_stable() {
        assert_eq!(super::alpha(), "alpha");
    }

    #[cfg(feature = "beta")]
    #[test]
    fn beta_is_stable() {
        assert_eq!(super::beta(), "beta");
    }
}
