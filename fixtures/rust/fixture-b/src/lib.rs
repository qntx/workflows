//! Fixture crate B for qntx/workflows end-to-end tests.

/// Adds two to the input by calling fixture-a twice.
#[must_use]
pub fn inc2(x: u64) -> u64 {
    fixture_a::inc(fixture_a::inc(x))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn inc2_adds_two() {
        assert_eq!(inc2(40), 42);
    }
}
