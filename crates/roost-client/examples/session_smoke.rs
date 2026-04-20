//! End-to-end M7-P3 smoke: create a session that runs `/bin/echo M7-DATA`,
//! attach a raw byte data conn, and prove the agent's output reaches us
//! through the ring/replay path.
//!
//! Run with:
//!   ROOST_HOSTD_PATH=target/debug/roost-hostd \
//!   cargo run -p roost-client --example session_smoke

use std::collections::BTreeMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

use base64::{Engine, engine::general_purpose::STANDARD};
use roost_client::roost_core::dto::AgentSpec;
use roost_client::{Client, ensure_hostd};
use serde_json::json;

fn main() {
    let client = Client::new();
    let info = client.host_info().expect("host_info");
    println!("hostd version={} pid={}", info.version, info.pid);

    let spec = AgentSpec {
        command: "/bin/echo M7-DATA-MARKER".into(),
        working_directory: String::new(),
        agent_kind: "shell".into(),
        rows: 24,
        cols: 80,
        env: BTreeMap::new(),
    };
    let session = client.create_session(spec).expect("create_session");
    println!(
        "created session id={} pid={:?} state={:?}",
        session.id, session.pid, session.state
    );

    // Give the agent a moment to print its line + exit; we attach AFTER the
    // child has produced output to prove ring replay works.
    std::thread::sleep(Duration::from_millis(250));

    let manifest = ensure_hostd().expect("manifest");
    let mut sock = UnixStream::connect(&manifest.socket).expect("connect data conn");
    sock.set_read_timeout(Some(Duration::from_secs(2))).unwrap();

    let mut hello = serde_json::to_string(&json!({
        "auth_token": manifest.auth_token,
        "session_id": session.id,
    }))
    .unwrap();
    hello.push('\n');
    sock.write_all(hello.as_bytes()).unwrap();

    let mut reader = BufReader::new(sock.try_clone().unwrap());
    let mut ack_line = String::new();
    reader.read_line(&mut ack_line).unwrap();
    println!("attach_ack: {}", ack_line.trim_end());
    let ack: serde_json::Value = serde_json::from_str(ack_line.trim_end()).unwrap();
    let replay_b64 = ack["replay_b64"].as_str().unwrap_or("");
    let replay = STANDARD.decode(replay_b64).unwrap_or_default();
    println!("replay bytes: {}", replay.len());
    let replay_text = String::from_utf8_lossy(&replay);
    println!("replay: {replay_text:?}");

    if replay_text.contains("M7-DATA-MARKER") {
        println!("OK: marker present in ring replay");
    } else {
        eprintln!("FAIL: marker missing from replay");
        std::process::exit(1);
    }

    // Drain a tiny bit of live stream too — ack + maybe trailing CR/LF
    // already covered, so this should EOF quickly since the agent already
    // exited.
    let mut more = Vec::new();
    let mut tmp = [0u8; 4096];
    while let Ok(n) = reader.get_mut().read(&mut tmp) {
        if n == 0 {
            break;
        }
        more.extend_from_slice(&tmp[..n]);
        if more.len() > 8 * 1024 {
            break;
        }
    }
    println!("post-replay bytes: {}", more.len());

    let sessions = client.list_sessions().expect("list_sessions");
    println!("now {} session(s) tracked", sessions.len());
    for s in sessions {
        println!(
            "  - id={} state={:?} exit_code={:?}",
            s.id, s.state, s.exit_code
        );
    }
}
