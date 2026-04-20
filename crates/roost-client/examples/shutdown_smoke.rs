//! M8 P1 smoke: spawn hostd, create a session running `sleep 30`, request
//! `shutdown(Stop)`, verify the daemon exits within the grace window and
//! the session pid is gone.
//!
//! Run with:
//!   ROOST_HOSTD_PATH=target/debug/roost-hostd \
//!   cargo run -p roost-client --example shutdown_smoke

use std::collections::BTreeMap;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use roost_client::roost_core::dto::AgentSpec;
use roost_client::roost_core::paths;
use roost_client::roost_core::rpc::ShutdownMode;
use roost_client::Client;

fn main() {
    let client = Client::new();
    let info = client.host_info().expect("host_info");
    println!("hostd pid={} version={}", info.pid, info.version);
    let hostd_pid = info.pid;

    let spec = AgentSpec {
        command: "/bin/sleep 30".into(),
        working_directory: String::new(),
        agent_kind: "shell".into(),
        rows: 24,
        cols: 80,
        env: BTreeMap::new(),
    };
    let session = client.create_session(spec).expect("create");
    println!("session id={} pid={:?}", session.id, session.pid);
    let session_pid = session.pid.expect("pid present");

    println!("requesting shutdown(Stop)…");
    let started = Instant::now();
    let ack = client.shutdown(ShutdownMode::Stop).expect("shutdown ack");
    println!("ack: live_sessions={}", ack.live_sessions);

    // Liveness signal: hostd is "gone" iff its socket no longer accepts.
    // (pid_alive on macOS gives false positives via kernel pid recycling.)
    let socket: PathBuf = paths::socket_path();
    let manifest = paths::manifest_path();
    let deadline = started + Duration::from_secs(7);
    let mut hostd_gone = false;
    let mut session_alive = true;
    while Instant::now() < deadline && (!hostd_gone || session_alive) {
        std::thread::sleep(Duration::from_millis(100));
        hostd_gone = !manifest.exists() && UnixStream::connect(&socket).is_err();
        session_alive = pid_alive(session_pid);
    }
    let elapsed_ms = started.elapsed().as_millis();
    println!(
        "after {} ms: hostd_gone={} session_alive={}",
        elapsed_ms, hostd_gone, session_alive
    );

    if !hostd_gone {
        eprintln!("FAIL: hostd socket still accepting after grace");
        std::process::exit(1);
    }
    if session_alive {
        eprintln!("FAIL: session pid still alive after grace");
        std::process::exit(1);
    }
    println!("OK: hostd + session both reaped within {} ms", elapsed_ms);
    let _ = hostd_pid;
}

fn pid_alive(pid: u32) -> bool {
    if pid == 0 {
        return false;
    }
    let rc = unsafe { libc::kill(pid as libc::pid_t, 0) };
    if rc == 0 {
        true
    } else {
        std::io::Error::last_os_error().raw_os_error() == Some(libc::EPERM)
    }
}
