fn main() {
    let mut args = std::env::args().skip(1);
    match args.next().as_deref() {
        Some("--version") => {
            println!("{}", version_line());
        }
        Some("--probe") => {
            println!("{}", version_line());
            println!("os-release: {}", os_release_pretty_name());
            let cross_env = if cfg!(fixture_cross_env) {
                "applied"
            } else {
                "unset"
            };
            println!("cross-env: {}", cross_env);
        }
        _ => {
            println!("fixture-bin: qntx/workflows release-rust e2e fixture");
        }
    }
}

fn version_line() -> String {
    let extra = if cfg!(feature = "extra") {
        " (extra)"
    } else {
        ""
    };
    format!("fixture-bin {}{}", env!("CARGO_PKG_VERSION"), extra)
}

fn os_release_pretty_name() -> String {
    let Ok(contents) = std::fs::read_to_string("/etc/os-release") else {
        return "unknown".to_string();
    };
    for line in contents.lines() {
        if let Some(value) = line.strip_prefix("PRETTY_NAME=") {
            return value.trim_matches('"').to_string();
        }
    }
    "unknown".to_string()
}
