//! `roost-attach <session_id>` — libghostty's child process. Bridges the
//! ghostty-owned PTY (our stdio) to a hostd session over Unix socket.
//!
//! Two connections, both to the same hostd UDS path:
//!   * **Control conn**: classic JSON-RPC. Used to push resize_session on
//!     SIGWINCH and to listen for `session_exited` so we can flush stdout
//!     and exit with the correct code.
//!   * **Data conn**: AttachHello → AttachAck → raw byte passthrough.
//!     stdin → socket → hostd → PTY master; PTY master → broadcast →
//!     socket → stdout. Replay (ring snapshot) is decoded from the ack and
//!     written to stdout before live bytes start.
//!
//! Sync std throughout — three threads total (stdin→sock, sock→stdout, ctrl
//! reader). Keeps the relay binary tiny and tokio-free; it's spawned per
//! session per app launch and we don't want a 4MB executable per agent.

use std::io::{BufRead, BufReader, Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::net::UnixStream;
use std::process::ExitCode;
use std::sync::Arc;
use std::sync::atomic::{AtomicI32, Ordering};
use std::thread;
use std::time::Duration;

use anyhow::{Context, Result, bail};
use base64::{Engine, engine::general_purpose::STANDARD};
use roost_core::dto::SessionId;
use roost_core::rpc::{
    self, AttachAck, AttachHello, Hello, HelloAck, Request, Response, events as event_methods,
    methods,
};
use serde_json::Value;

const HELLO_TIMEOUT: Duration = Duration::from_secs(2);

fn main() -> ExitCode {
    if let Err(e) = run() {
        eprintln!("roost-attach: {e:#}");
        return ExitCode::from(1);
    }
    ExitCode::from(0)
}

fn run() -> Result<()> {
    let sid = parse_args()?;
    let socket = std::env::var("ROOST_HOSTD_SOCKET")
        .context("ROOST_HOSTD_SOCKET env var required")?;
    let token = std::env::var("ROOST_AUTH_TOKEN")
        .context("ROOST_AUTH_TOKEN env var required")?;

    // Control conn first — gives us a place to push resize requests and
    // listen for session_exited.
    let mut ctrl = open_control_conn(&socket, &token)?;
    let data = open_data_conn(&socket, &token, sid)?;

    // Reader of the ctrl conn: looking specifically for session_exited
    // matching `sid`, then signal the main loop to drain + exit.
    let exit_code = Arc::new(AtomicI32::new(i32::MIN));
    let exit_code_for_thread = exit_code.clone();
    let target_sid = sid;
    thread::Builder::new()
        .name("roost-attach-ctrl".into())
        .spawn(move || ctrl_event_loop(&mut ctrl, target_sid, exit_code_for_thread))?;

    // SIGWINCH → resize. Capture the writer side of the ctrl socket; the
    // signal handler enqueues resize requests to a background thread.
    install_resize_pump(&socket, &token, sid)?;

    // Data conn: split into halves, pump stdin↔socket↔stdout.
    let read_half = data.try_clone()?;
    let write_half = data.try_clone()?;
    drop(data);

    let stdout_thread = thread::Builder::new()
        .name("roost-attach-out".into())
        .spawn(move || socket_to_stdout(read_half))?;
    let stdin_thread = thread::Builder::new()
        .name("roost-attach-in".into())
        .spawn(move || stdin_to_socket(write_half))?;

    // Wait for the stdout pump to exit (data conn EOF). Stdin pump can be
    // dropped — closing stdin or our process death tears it down.
    let _ = stdout_thread.join();
    drop(stdin_thread);

    // Mirror the agent's exit code when we observed one; std::process::exit
    // is the only way to carry a non-zero status out of `Result<()>`.
    let code = exit_code.load(Ordering::SeqCst);
    if code != i32::MIN && code != 0 {
        std::process::exit(code);
    }
    Ok(())
}

fn parse_args() -> Result<SessionId> {
    let mut args = std::env::args().skip(1);
    let raw = args
        .next()
        .ok_or_else(|| anyhow::anyhow!("usage: roost-attach <session_id>"))?;
    raw.parse::<SessionId>()
        .map_err(|e| anyhow::anyhow!("invalid session id {raw:?}: {e}"))
}

fn open_control_conn(socket: &str, token: &str) -> Result<UnixStream> {
    let stream = UnixStream::connect(socket)
        .with_context(|| format!("connect ctrl conn at {socket}"))?;
    stream.set_read_timeout(Some(HELLO_TIMEOUT))?;
    stream.set_write_timeout(Some(HELLO_TIMEOUT))?;

    let hello = Hello {
        auth_token: token.to_string(),
        client_version: env!("CARGO_PKG_VERSION").to_string(),
    };
    write_line(&stream, &hello)?;
    let ack: HelloAck = read_line(&stream)?;
    if !ack.ok {
        bail!("ctrl hello rejected: {:?}", ack.error);
    }
    // Reader thread blocks indefinitely; writes have a generous ceiling.
    stream.set_read_timeout(None)?;
    stream.set_write_timeout(Some(Duration::from_secs(30)))?;
    Ok(stream)
}

fn open_data_conn(socket: &str, token: &str, sid: SessionId) -> Result<UnixStream> {
    let stream = UnixStream::connect(socket)
        .with_context(|| format!("connect data conn at {socket}"))?;
    stream.set_read_timeout(Some(HELLO_TIMEOUT))?;
    stream.set_write_timeout(Some(HELLO_TIMEOUT))?;

    let hello = AttachHello {
        auth_token: token.to_string(),
        session_id: sid,
    };
    write_line(&stream, &hello)?;
    let ack: AttachAck = read_line(&stream)?;
    if !ack.ok {
        bail!("attach rejected: {:?}", ack.error);
    }

    // Replay the ring snapshot to stdout before switching to live mode.
    if !ack.replay_b64.is_empty() {
        let bytes = STANDARD
            .decode(ack.replay_b64.as_bytes())
            .context("decode replay_b64")?;
        let mut stdout = std::io::stdout().lock();
        stdout.write_all(&bytes).ok();
        stdout.flush().ok();
    }

    // Switch to long-lived raw byte mode.
    stream.set_read_timeout(None)?;
    stream.set_write_timeout(Some(Duration::from_secs(30)))?;
    Ok(stream)
}

fn ctrl_event_loop(stream: &mut UnixStream, target: SessionId, exit_code: Arc<AtomicI32>) {
    let reader = stream.try_clone();
    let Ok(reader) = reader else { return };
    let mut br = BufReader::new(reader);
    let mut buf = String::new();
    loop {
        buf.clear();
        let n = match br.read_line(&mut buf) {
            Ok(n) => n,
            Err(_) => return,
        };
        if n == 0 {
            return;
        }
        let raw: Value = match serde_json::from_str(buf.trim_end_matches('\n')) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let Some(method) = raw.get("method").and_then(|v| v.as_str()) else {
            continue;
        };
        if method != event_methods::SESSION_EXITED {
            continue;
        }
        let params = raw.get("params");
        let sid_match = params
            .and_then(|p| p.get("session_id"))
            .and_then(|v| v.as_str())
            .and_then(|s| s.parse::<SessionId>().ok())
            == Some(target);
        if !sid_match {
            continue;
        }
        let code = params
            .and_then(|p| p.get("exit_code"))
            .and_then(|v| v.as_i64())
            .map(|c| c as i32)
            .unwrap_or(0);
        exit_code.store(code, Ordering::SeqCst);
        // Closing the ctrl socket here would race the resize-pump thread;
        // let the data conn EOF drive the actual teardown.
        return;
    }
}

fn install_resize_pump(socket: &str, token: &str, sid: SessionId) -> Result<()> {
    use signal_hook::consts::SIGWINCH;
    use signal_hook::iterator::Signals;

    let mut signals = Signals::new([SIGWINCH])?;
    let socket = socket.to_string();
    let token = token.to_string();

    thread::Builder::new()
        .name("roost-attach-winch".into())
        .spawn(move || {
            for _sig in &mut signals {
                let Ok(conn) = open_resize_conn(&socket, &token) else {
                    continue;
                };
                let Some((rows, cols)) = current_winsize() else {
                    continue;
                };
                let req = Request::new(
                    1,
                    methods::RESIZE_SESSION,
                    rpc::ResizeSessionParams {
                        session_id: sid,
                        rows,
                        cols,
                    },
                );
                if write_line(&conn, &req).is_err() {
                    continue;
                }
                let _: Result<Response> = read_line(&conn);
            }
        })?;
    Ok(())
}

fn open_resize_conn(socket: &str, token: &str) -> Result<UnixStream> {
    let stream = UnixStream::connect(socket)?;
    stream.set_read_timeout(Some(HELLO_TIMEOUT))?;
    stream.set_write_timeout(Some(HELLO_TIMEOUT))?;
    let hello = Hello {
        auth_token: token.to_string(),
        client_version: env!("CARGO_PKG_VERSION").to_string(),
    };
    write_line(&stream, &hello)?;
    let ack: HelloAck = read_line(&stream)?;
    if !ack.ok {
        bail!("resize hello rejected: {:?}", ack.error);
    }
    Ok(stream)
}

fn current_winsize() -> Option<(u16, u16)> {
    // SAFETY: ioctl with TIOCGWINSZ on stdout's fd is the standard way to
    // read terminal size; portable on macOS / Linux. winsize layout matches
    // libc::winsize exactly.
    let mut ws: libc::winsize = unsafe { std::mem::zeroed() };
    let fd = std::io::stdout().as_raw_fd();
    let rc = unsafe { libc::ioctl(fd, libc::TIOCGWINSZ, &mut ws) };
    if rc == 0 {
        Some((ws.ws_row, ws.ws_col))
    } else {
        None
    }
}

fn socket_to_stdout(mut sock: UnixStream) {
    let mut stdout = std::io::stdout().lock();
    let mut buf = [0u8; 4096];
    loop {
        match sock.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                if stdout.write_all(&buf[..n]).is_err() {
                    break;
                }
                if stdout.flush().is_err() {
                    break;
                }
            }
            Err(_) => break,
        }
    }
}

fn stdin_to_socket(mut sock: UnixStream) {
    let stdin = std::io::stdin();
    let mut handle = stdin.lock();
    let mut buf = [0u8; 4096];
    loop {
        let n = match handle.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => n,
            Err(_) => break,
        };
        if sock.write_all(&buf[..n]).is_err() {
            break;
        }
    }
    // EOF on stdin → half-close the socket so hostd sees EOF on the agent's
    // stdin too. Best-effort; some agents don't care.
    let _ = sock.shutdown(std::net::Shutdown::Write);
}

fn write_line<T: serde::Serialize>(mut stream: &UnixStream, msg: &T) -> Result<()> {
    let mut s = serde_json::to_string(msg)?;
    s.push('\n');
    stream.write_all(s.as_bytes())?;
    stream.flush()?;
    Ok(())
}

fn read_line<T: serde::de::DeserializeOwned>(stream: &UnixStream) -> Result<T> {
    let mut br = BufReader::new(stream);
    let mut buf = String::new();
    let n = br.read_line(&mut buf)?;
    if n == 0 {
        bail!("EOF before frame");
    }
    let v = serde_json::from_str(buf.trim_end_matches('\n'))?;
    Ok(v)
}
