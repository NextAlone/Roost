//! Quick connectivity check: ensure_hostd → host_info → is_jj_repo("/").
//! Run with: ROOST_HOSTD_PATH=target/debug/roost-hostd cargo run -p roost-client --example smoke

fn main() {
    let client = roost_client::Client::new();
    let info = client.host_info().expect("host_info");
    println!(
        "hostd version={} pid={} uptime={}s sessions={}",
        info.version, info.pid, info.uptime_secs, info.session_count
    );
    let here = std::env::current_dir().unwrap();
    let is = client
        .is_jj_repo(&here.to_string_lossy())
        .expect("is_jj_repo");
    println!("is_jj_repo({:?}) = {}", here, is);
    let ver = client.jj_version().expect("jj_version");
    println!("jj version: {}", ver);

    // Cover one each of RepoDirParams/WorkspaceListResult and
    // WorkspaceDirParams/StatusResult — by structural analogy this validates
    // the wire shape every other method shares.
    let cwd = here.to_string_lossy().into_owned();
    let workspaces = client.list_workspaces(&cwd).expect("list_workspaces");
    println!("workspaces: {} entries", workspaces.len());
    for w in &workspaces {
        println!("  - {} @ {} ({})", w.name, w.path, w.change_id);
    }
    let status = client.workspace_status(&cwd).expect("workspace_status");
    println!("status: clean={} ({} lines)", status.clean, status.lines.len());
}
