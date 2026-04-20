//! M8 P1: shutdown(Release) smoke. Manifest should disappear, but hostd
//! and session keep running. Re-spawning ensures the next adopt walks the
//! "no manifest → spawn" path.

use std::collections::BTreeMap;
use std::time::Duration;

use roost_client::roost_core::dto::AgentSpec;
use roost_client::roost_core::paths;
use roost_client::roost_core::rpc::ShutdownMode;
use roost_client::Client;

fn main() {
    let client = Client::new();
    let info = client.host_info().expect("host_info");
    println!("hostd pid={}", info.pid);
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
    let session_pid = session.pid.expect("pid");
    println!("session pid={}", session_pid);

    let ack = client.shutdown(ShutdownMode::Release).expect("release");
    println!("release ack: {} live", ack.live_sessions);

    std::thread::sleep(Duration::from_millis(300));

    let manifest_gone = !paths::manifest_path().exists();
    let hostd_alive = pid_alive(hostd_pid);
    let session_alive = pid_alive(session_pid);
    println!(
        "after release: manifest_gone={} hostd_alive={} session_alive={}",
        manifest_gone, hostd_alive, session_alive
    );

    if !manifest_gone {
        eprintln!("FAIL: manifest should be removed by Release");
        std::process::exit(1);
    }
    if !hostd_alive {
        eprintln!("FAIL: hostd should still be running after Release");
        // Cleanup the session we leaked.
        unsafe { libc::kill(session_pid as libc::pid_t, libc::SIGTERM); }
        std::process::exit(1);
    }
    if !session_alive {
        eprintln!("FAIL: session should still be running after Release");
        std::process::exit(1);
    }
    println!("OK: manifest gone, hostd + session both alive");

    // Cleanup so we don't leave a sleep 30 behind.
    unsafe { libc::kill(hostd_pid as libc::pid_t, libc::SIGTERM); }
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
