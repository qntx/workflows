//! Fixture crate for the `CI / Rust fuzz` end-to-end job.

/// First byte of `data`, or `0` when empty.
#[must_use]
pub fn first_byte(data: &[u8]) -> u8 {
    data.first().copied().unwrap_or(0)
}

/// Byte length of the longest run of `needle` in `data`.
#[must_use]
pub fn longest_run(data: &[u8], needle: u8) -> usize {
    let mut best = 0;
    let mut run = 0;
    for &b in data {
        if b == needle {
            run += 1;
            best = best.max(run);
        } else {
            run = 0;
        }
    }
    best
}
