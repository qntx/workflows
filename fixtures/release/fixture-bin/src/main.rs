fn main() {
    let mut args = std::env::args().skip(1);
    if args.next().as_deref() == Some("--version") {
        let extra = if cfg!(feature = "extra") { " (extra)" } else { "" };
        println!("fixture-bin {}{}", env!("CARGO_PKG_VERSION"), extra);
        return;
    }
    println!("fixture-bin: qntx/workflows release-rust e2e fixture");
}
