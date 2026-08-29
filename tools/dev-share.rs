use std::env;
use std::io::{BufRead, BufReader};
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr, TcpStream};
use std::process::{Command, ExitCode, Stdio};
use std::time::Duration;

const USAGE: &str = "usage: dev-share <quick|secure> http://127.0.0.1:<port>";

#[derive(Debug, PartialEq, Eq)]
enum Mode {
    Quick,
    Secure,
}

#[derive(Debug, PartialEq, Eq)]
struct Origin {
    url: String,
    socket: SocketAddr,
}

#[derive(Debug, PartialEq, Eq)]
struct Invocation {
    mode: Mode,
    origin: Origin,
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("dev-share: {message}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<(), String> {
    let invocation = parse_invocation(env::args().skip(1))?;
    require_reachable(&invocation.origin)?;
    match invocation.mode {
        Mode::Quick => run_quick(&invocation.origin),
        Mode::Secure => run_secure(&invocation.origin),
    }
}

fn parse_invocation(arguments: impl IntoIterator<Item = String>) -> Result<Invocation, String> {
    let mut arguments = arguments.into_iter();
    let mode = match arguments.next().as_deref() {
        Some("quick") => Mode::Quick,
        Some("secure") => Mode::Secure,
        _ => return Err(USAGE.to_owned()),
    };
    let raw_origin = arguments.next().ok_or_else(|| USAGE.to_owned())?;
    if arguments.next().is_some() {
        return Err(USAGE.to_owned());
    }
    Ok(Invocation {
        mode,
        origin: parse_origin(&raw_origin)?,
    })
}

fn parse_origin(raw: &str) -> Result<Origin, String> {
    let authority = raw
        .strip_prefix("http://")
        .ok_or_else(|| "origin must use explicit http:// loopback transport".to_owned())?
        .strip_suffix('/')
        .unwrap_or_else(|| raw.strip_prefix("http://").expect("prefix checked"));
    if authority.contains(['/', '?', '#', '@']) {
        return Err("origin must not contain credentials, a path, query, or fragment".to_owned());
    }

    let (ip, raw_port) = if let Some(port) = authority.strip_prefix("127.0.0.1:") {
        (IpAddr::V4(Ipv4Addr::LOCALHOST), port)
    } else if let Some(port) = authority.strip_prefix("[::1]:") {
        (IpAddr::V6(Ipv6Addr::LOCALHOST), port)
    } else {
        return Err("origin host must be literal 127.0.0.1 or [::1]".to_owned());
    };
    let port = raw_port
        .parse::<u16>()
        .map_err(|_| "origin must declare a valid non-zero port".to_owned())?;
    if port == 0 {
        return Err("origin must declare a valid non-zero port".to_owned());
    }
    let socket = SocketAddr::new(ip, port);
    Ok(Origin {
        url: format!("http://{socket}"),
        socket,
    })
}

fn require_reachable(origin: &Origin) -> Result<(), String> {
    TcpStream::connect_timeout(&origin.socket, Duration::from_secs(2))
        .map(|_| ())
        .map_err(|error| {
            format!(
                "origin {} is not accepting connections: {error}",
                origin.url
            )
        })
}

fn run_quick(origin: &Origin) -> Result<(), String> {
    let mut child = Command::new("cloudflared")
        .args([
            "tunnel",
            "--config",
            "/dev/null",
            "--no-autoupdate",
            "--url",
            &origin.url,
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("could not start cloudflared: {error}"))?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| "cloudflared stderr was unavailable".to_owned())?;
    let mut presented = false;
    for line in BufReader::new(stderr).lines() {
        let line = line.map_err(|error| format!("could not read cloudflared output: {error}"))?;
        eprintln!("{line}");
        if !presented && let Some(url) = extract_quick_url(&line) {
            present(
                &url,
                Some("public: anyone with this temporary URL can connect"),
            )?;
            presented = true;
        }
    }
    let status = child
        .wait()
        .map_err(|error| format!("could not wait for cloudflared: {error}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("cloudflared exited with {status}"))
    }
}

fn run_secure(origin: &Origin) -> Result<(), String> {
    let public_url = required_environment("DEV_SHARE_PUBLIC_URL")?;
    let caddy_config = required_environment("DEV_SHARE_CADDY_CONFIG")?;
    let lock_file = required_environment("DEV_SHARE_LOCK_FILE")?;
    present(&public_url, Some("protected by Cloudflare Access"))?;
    let status = Command::new("flock")
        .args([
            "--nonblock",
            "--conflict-exit-code",
            "75",
            &lock_file,
            "caddy",
            "run",
            "--config",
            &caddy_config,
            "--adapter",
            "caddyfile",
        ])
        .env("DEV_SHARE_ORIGIN", &origin.url)
        .status()
        .map_err(|error| format!("could not start the secure reverse proxy: {error}"))?;
    if status.code() == Some(75) {
        Err("another secure share already owns the workstation gateway".to_owned())
    } else if status.success() {
        Ok(())
    } else {
        Err(format!("secure reverse proxy exited with {status}"))
    }
}

fn required_environment(name: &str) -> Result<String, String> {
    env::var(name).map_err(|_| format!("required adapter configuration {name} is missing"))
}

fn present(url: &str, note: Option<&str>) -> Result<(), String> {
    println!("\n{url}");
    if let Some(note) = note {
        println!("{note}\n");
    }
    let status = Command::new("qrencode")
        .args(["-t", "ANSIUTF8", "-m", "1", url])
        .status()
        .map_err(|error| format!("could not render QR code: {error}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("qrencode exited with {status}"))
    }
}

fn extract_quick_url(line: &str) -> Option<String> {
    let start = line.find("https://")?;
    let candidate = &line[start..];
    let end = candidate
        .find(|character: char| {
            !(character.is_ascii_alphanumeric() || matches!(character, ':' | '/' | '.' | '-'))
        })
        .unwrap_or(candidate.len());
    let url = &candidate[..end];
    url.ends_with(".trycloudflare.com").then(|| url.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_only_explicit_literal_loopback_origins() {
        assert_eq!(
            parse_origin("http://127.0.0.1:8788/").unwrap(),
            Origin {
                url: "http://127.0.0.1:8788".to_owned(),
                socket: "127.0.0.1:8788".parse().unwrap(),
            }
        );
        assert_eq!(
            parse_origin("http://[::1]:3000").unwrap().socket,
            "[::1]:3000".parse().unwrap()
        );
        for invalid in [
            "https://127.0.0.1:8788",
            "http://localhost:8788",
            "http://192.168.1.20:8788",
            "http://127.0.0.1",
            "http://127.0.0.1:0",
            "http://user@127.0.0.1:8788",
            "http://127.0.0.1:8788/admin",
            "http://127.0.0.1:8788?debug=true",
        ] {
            assert!(parse_origin(invalid).is_err(), "accepted {invalid}");
        }
    }

    #[test]
    fn parses_the_two_explicit_modes_without_hidden_defaults() {
        assert_eq!(
            parse_invocation(["secure".to_owned(), "http://127.0.0.1:8788".to_owned()])
                .unwrap()
                .mode,
            Mode::Secure
        );
        assert!(parse_invocation(["http://127.0.0.1:8788".to_owned()]).is_err());
    }

    #[test]
    fn extracts_only_complete_trycloudflare_urls() {
        assert_eq!(
            extract_quick_url("INF | https://quiet-tree.trycloudflare.com | ready"),
            Some("https://quiet-tree.trycloudflare.com".to_owned())
        );
        assert_eq!(extract_quick_url("https://example.com"), None);
    }
}
