//! Fixture crate for the `CI / Bun` `rust: true` end-to-end job.

/// Adds one to the input.
#[must_use]
pub fn inc(x: u64) -> u64 {
    x + 1
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn inc_adds_one() {
        assert_eq!(inc(41), 42);
    }
}
