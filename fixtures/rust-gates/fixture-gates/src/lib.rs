//! Fixture crate for the self-CI independent-gates proof: the Deny and
//! Clippy gates fail on purpose while Format, Build, Test, and Doc pass.

/// Returns the input unchanged.
#[must_use]
pub fn identity(x: u64) -> u64 {
    // Intentional: `needless_return` trips `clippy -D warnings` so the e2e
    // run has a second red gate next to Deny.
    return x;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identity_round_trips() {
        assert_eq!(identity(42), 42);
    }
}
