//! Incremental OSC scanner. Feeds bytes from the PTY one chunk at a time;
//! emits a callback for each complete OSC sequence whose number is in the
//! whitelist. Anything else (other OSCs, regular text, control codes) is
//! ignored — the byte stream is still passed through to subscribers
//! unchanged.
//!
//! Spec recap: OSC = `ESC ]` num `;` payload TERM, where TERM is BEL (0x07)
//! or ST (`ESC \`). We cap accumulator size to avoid unbounded growth on a
//! malformed stream.

const MAX_OSC_BYTES: usize = 4 * 1024;

/// Numeric OSC sequences hostd surfaces as events. Anything outside this
/// list is dropped on the floor (still passes through PTY).
pub const WHITELIST: &[u32] = &[9, 99, 777];

#[derive(Debug)]
enum State {
    Idle,
    SeenEsc,
    InOsc { buf: Vec<u8> },
    InOscSeenEsc { buf: Vec<u8> },
}

pub struct OscScanner {
    state: State,
}

impl Default for OscScanner {
    fn default() -> Self {
        Self::new()
    }
}

impl OscScanner {
    pub fn new() -> Self {
        Self { state: State::Idle }
    }

    /// Push a chunk of bytes; invoke `emit(seq, payload)` for each whitelisted
    /// OSC found. Bytes are not mutated; pass-through stays the caller's job.
    pub fn push<F>(&mut self, bytes: &[u8], mut emit: F)
    where
        F: FnMut(u32, &str),
    {
        for &b in bytes {
            self.feed(b, &mut emit);
        }
    }

    fn feed<F>(&mut self, b: u8, emit: &mut F)
    where
        F: FnMut(u32, &str),
    {
        // Replace state out-of-place to avoid borrow gymnastics.
        let prev = std::mem::replace(&mut self.state, State::Idle);
        self.state = match prev {
            State::Idle => {
                if b == 0x1b {
                    State::SeenEsc
                } else {
                    State::Idle
                }
            }
            State::SeenEsc => {
                if b == b']' {
                    State::InOsc { buf: Vec::new() }
                } else if b == 0x1b {
                    State::SeenEsc
                } else {
                    State::Idle
                }
            }
            State::InOsc { mut buf } => {
                if b == 0x07 {
                    self.dispatch(&buf, emit);
                    State::Idle
                } else if b == 0x1b {
                    State::InOscSeenEsc { buf }
                } else {
                    if buf.len() < MAX_OSC_BYTES {
                        buf.push(b);
                    }
                    State::InOsc { buf }
                }
            }
            State::InOscSeenEsc { mut buf } => {
                if b == b'\\' {
                    self.dispatch(&buf, emit);
                    State::Idle
                } else {
                    // False alarm — the ESC was data, not the start of ST.
                    if buf.len() < MAX_OSC_BYTES {
                        buf.push(0x1b);
                    }
                    if b == 0x1b {
                        State::InOscSeenEsc { buf }
                    } else {
                        if buf.len() < MAX_OSC_BYTES {
                            buf.push(b);
                        }
                        State::InOsc { buf }
                    }
                }
            }
        };
    }

    fn dispatch<F>(&self, buf: &[u8], emit: &mut F)
    where
        F: FnMut(u32, &str),
    {
        // Format: `<num>;<payload>`. If no `;` the OSC is malformed; ignore.
        let Some(sep) = buf.iter().position(|&c| c == b';') else {
            return;
        };
        let num_bytes = &buf[..sep];
        let payload = &buf[sep + 1..];
        let Ok(num_str) = std::str::from_utf8(num_bytes) else {
            return;
        };
        let Ok(seq) = num_str.parse::<u32>() else {
            return;
        };
        if !WHITELIST.contains(&seq) {
            return;
        }
        let payload = String::from_utf8_lossy(payload);
        emit(seq, &payload);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn collect(bytes: &[u8]) -> Vec<(u32, String)> {
        let mut s = OscScanner::new();
        let mut out = Vec::new();
        s.push(bytes, |seq, payload| out.push((seq, payload.to_string())));
        out
    }

    #[test]
    fn osc_9_bel_terminated() {
        let r = collect(b"\x1b]9;hello\x07");
        assert_eq!(r, vec![(9, "hello".into())]);
    }

    #[test]
    fn osc_777_st_terminated() {
        let r = collect(b"\x1b]777;notify;hi;world\x1b\\");
        assert_eq!(r, vec![(777, "notify;hi;world".into())]);
    }

    #[test]
    fn ignores_non_whitelisted() {
        // OSC 0 = window title; not in whitelist.
        let r = collect(b"\x1b]0;some title\x07");
        assert!(r.is_empty());
    }

    #[test]
    fn ignores_garbage_in_between() {
        let r = collect(b"hello\x1b]9;a\x07world\x1b]99;b\x07!");
        assert_eq!(r, vec![(9, "a".into()), (99, "b".into())]);
    }

    #[test]
    fn handles_chunked_input() {
        let mut s = OscScanner::new();
        let mut out = Vec::new();
        let mut sink = |seq, payload: &str| out.push((seq, payload.to_string()));
        s.push(b"\x1b]9;he", &mut sink);
        s.push(b"llo\x07rest", &mut sink);
        assert_eq!(out, vec![(9, "hello".into())]);
    }

    #[test]
    fn caps_oversized_osc() {
        let mut payload = vec![b'A'; MAX_OSC_BYTES + 1024];
        let mut input = b"\x1b]9;".to_vec();
        input.append(&mut payload);
        input.push(0x07);
        let r = collect(&input);
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].0, 9);
        // Payload truncated at cap.
        assert!(r[0].1.len() <= MAX_OSC_BYTES);
    }
}
