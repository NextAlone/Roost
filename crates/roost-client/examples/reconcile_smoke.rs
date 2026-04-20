//! M8 P3 smoke: create a session, simulate hostd crash (SIGKILL), spawn a
//! new hostd, verify the surviving SQLite row is reconciled to ExitedLost.

use std::collections::BTreeMap;
use std::time::Duration;

use roost_client::roost_core::dto::{AgentSpec, SessionState};
use roost_client::roost_core::paths;
use roost_client::Client;

fn main() {
    // Phase 1: spawn hostd, create a session, then kill -9 hostd. The
    // SQLite row stays as state='running' because the wait task never
    // gets to fire its update.
    let c1 = Client::new();
    let info = c1.host_info().expect("host_info");
    let hostd_pid = info.pid;
    println!("phase1 hostd pid={}", hostd_pid);

    let spec = AgentSpec {
        command: "/bin/sleep 30".into(),
        working_directory: String::new(),
        agent_kind: "shell".into(),
        rows: 24,
        cols: 80,
        env: BTreeMap::new(),
    };
    let session = c1.create_session(spec).expect("create");
    let sid = session.id;
    let session_pid = session.pid.expect("pid");
    println!("created sid={} session_pid={}", sid, session_pid);
    // Give the insert task a moment to commit.
    std::thread::sleep(Duration::from_millis(150));

    // Drop the client → connection closes; hostd is SIGKILLed below so
    // there's no chance to clean up gracefully.
    drop(c1);

    println!("phase1: kill -9 hostd pid={hostd_pid}");
    unsafe { libc::kill(hostd_pid as libc::pid_t, libc::SIGKILL); }
    // Reap the (SIGHUPed) sleep too, since hostd's PTY master is now closed.
    std::thread::sleep(Duration::from_millis(300));
    if pid_alive(session_pid) {
        unsafe { libc::kill(session_pid as libc::pid_t, libc::SIGKILL); }
    }

    // Manifest + socket may still be on disk because SIGKILL skipped panic
    // handler. Remove them so the next Client spawn doesn't think the dead
    // pid is alive.
    let _ = std::fs::remove_file(paths::manifest_path());
    let _ = std::fs::remove_file(paths::socket_path());

    // Phase 2: fresh client → spawns a new hostd → reconcile_orphans
    // should turn the leftover row into ExitedLost.
    let c2 = Client::new();
    let info2 = c2.host_info().expect("host_info round 2");
    println!("phase2 hostd pid={}", info2.pid);
    assert!(
        info2.pid != hostd_pid,
        "hostd pid should have changed across restart"
    );

    let history = c2.list_session_history().expect("history");
    println!("history: {} entries", history.len());
    let row = history
        .iter()
        .find(|h| h.id == sid)
        .expect("session should be in history");
    println!(
        "  - id={} state={:?} exit_code={:?}",
        row.id, row.state, row.exit_code
    );
    if row.state != SessionState::ExitedLost {
        eprintln!("FAIL: expected ExitedLost, got {:?}", row.state);
        std::process::exit(1);
    }
    println!("OK: stale Running row reconciled to ExitedLost");

    // Cleanup the daemon we spawned for the test.
    let _ = c2.shutdown(roost_client::roost_core::rpc::ShutdownMode::Stop);
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
