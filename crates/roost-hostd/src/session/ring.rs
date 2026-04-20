//! Fixed-capacity byte ring. Lets a late attacher replay the last N KB of
//! PTY output before switching to the live `broadcast` channel.
//!
//! No OSC-aware truncation yet — advisor's "cut on OSC boundary" refinement
//! is flagged in design.md §6-M7 risks; for P1 we keep it dumb. Attach-time
//! replay can show a torn escape sequence; fixing that is a P3+ polish.

use bytes::Bytes;
use std::collections::VecDeque;

/// Default scrollback budget. Bigger than a typical screen, small enough that
/// 20 sessions total cost ~5MB.
pub const DEFAULT_CAPACITY_BYTES: usize = 256 * 1024;

pub struct RingBuffer {
    capacity: usize,
    buf: VecDeque<u8>,
}

impl RingBuffer {
    pub fn new(capacity: usize) -> Self {
        Self {
            capacity,
            buf: VecDeque::with_capacity(capacity),
        }
    }

    pub fn push(&mut self, bytes: &[u8]) {
        // Cap writes larger than the whole buffer — only the tail matters.
        let bytes = if bytes.len() > self.capacity {
            &bytes[bytes.len() - self.capacity..]
        } else {
            bytes
        };
        let overflow = (self.buf.len() + bytes.len()).saturating_sub(self.capacity);
        for _ in 0..overflow {
            self.buf.pop_front();
        }
        self.buf.extend(bytes.iter().copied());
    }

    pub fn snapshot(&self) -> Bytes {
        let (a, b) = self.buf.as_slices();
        if b.is_empty() {
            Bytes::copy_from_slice(a)
        } else {
            let mut v = Vec::with_capacity(a.len() + b.len());
            v.extend_from_slice(a);
            v.extend_from_slice(b);
            Bytes::from(v)
        }
    }

    pub fn len(&self) -> usize {
        self.buf.len()
    }

    pub fn is_empty(&self) -> bool {
        self.buf.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn push_under_capacity_preserves_all() {
        let mut r = RingBuffer::new(16);
        r.push(b"hello");
        r.push(b" world");
        assert_eq!(r.snapshot().as_ref(), b"hello world");
    }

    #[test]
    fn push_over_capacity_keeps_tail() {
        let mut r = RingBuffer::new(8);
        r.push(b"abcdefgh");
        r.push(b"ij");
        assert_eq!(r.snapshot().as_ref(), b"cdefghij");
    }

    #[test]
    fn single_push_bigger_than_capacity_keeps_tail() {
        let mut r = RingBuffer::new(4);
        r.push(b"abcdefghij");
        assert_eq!(r.snapshot().as_ref(), b"ghij");
    }
}
