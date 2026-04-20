//! Generates Swift bindings from the `#[swift_bridge::bridge]` module in
//! `src/lib.rs`. Output goes under `$CARGO_TARGET_DIR/swift-bridge/` and is
//! copied into the consumer Xcode project by `pocs/swift-bridge-hello/scripts/build-rust.sh`.

fn main() {
    let out_dir = std::env::var("OUT_DIR").expect("OUT_DIR not set by cargo");
    let crate_name = env!("CARGO_PKG_NAME");

    let bridges = vec!["src/lib.rs"];
    for b in &bridges {
        println!("cargo:rerun-if-changed={b}");
    }

    swift_bridge_build::parse_bridges(bridges)
        .write_all_concatenated(out_dir, crate_name);
}
