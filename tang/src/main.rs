use std::env;
use std::ffi::OsString;
use std::fs;
use std::io::{self, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::{thread, time::Duration};

use anyhow::{Context, Result, bail, ensure};
use clap::{Args, Parser, Subcommand};

const DEVICE: &str = "GW2AR-LV18QN88C8/I7";
const FAMILY: &str = "GW2A-18C";

#[derive(Parser)]
#[command(version, about)]
struct Cli {
    #[command(subcommand)]
    action: Action,
}

#[derive(Subcommand)]
enum Action {
    /// Check Verilog syntax and module connections with Icarus Verilog.
    Check {
        /// Verilog source files to check together.
        #[arg(required = true, value_name = "SOURCE")]
        sources: Vec<PathBuf>,
        /// Check one top-level module; by default Icarus discovers the roots.
        #[arg(long, value_parser = module_name)]
        top: Option<String>,
    },
    /// Build a .fs bitstream in build/ alongside the first source.
    Build(Design),
    /// Load an existing .fs file into the board's SRAM.
    Load { bitstream: PathBuf },
    /// Build the design, then load it into SRAM.
    Run(Design),
}

#[derive(Args)]
struct Design {
    /// Verilog source files, main file first.
    #[arg(required = true, value_name = "SOURCE")]
    sources: Vec<PathBuf>,
    /// Pin constraints (defaults to a matching .cst or the shared board pin map).
    #[arg(long)]
    cst: Option<PathBuf>,
    /// Top-level Verilog module.
    #[arg(long, default_value = "top", value_parser = module_name)]
    top: String,
}

fn module_name(name: &str) -> Result<String, String> {
    let mut chars = name.chars();
    if chars
        .next()
        .is_some_and(|c| c == '_' || c.is_ascii_alphabetic())
        && chars.all(|c| c == '_' || c == '$' || c.is_ascii_alphanumeric())
    {
        Ok(name.to_owned())
    } else {
        Err("expected a simple Verilog module name, such as top".into())
    }
}

fn checked(command: &mut Command) -> Result<()> {
    let name = command.get_program().display().to_string();
    let status = command
        .status()
        .with_context(|| format!("could not start {name}"))?;
    ensure!(status.success(), "{name} failed ({status})");
    Ok(())
}

fn board_project(main: &Path) -> Result<Option<&Path>> {
    for parent in main.ancestors().skip(1) {
        if parent.join("tang/pins/nano20k.cst").try_exists()? {
            return Ok(Some(parent));
        }
    }
    Ok(None)
}

fn board_pins(project: Option<&Path>, scratch: &Path) -> Result<PathBuf> {
    if let Some(root) = project {
        return Ok(root.join("tang/pins/nano20k.cst"));
    }
    // A standalone installation also works outside the project tree.
    let pins = scratch.join("nano20k.cst");
    fs::write(&pins, include_bytes!("../pins/nano20k.cst"))?;
    Ok(pins)
}

fn source_paths(files: &[PathBuf]) -> Result<Vec<PathBuf>> {
    let mut sources = Vec::new();
    for path in files {
        ensure!(
            path.extension()
                .is_some_and(|ext| ext == "v" || ext == "sv"),
            "expected a .v or .sv source: {}",
            path.display()
        );
        sources.push(
            path.canonicalize()
                .with_context(|| format!("opening {}", path.display()))?,
        );
    }
    Ok(sources)
}

fn check(files: &[PathBuf], top: Option<&str>) -> Result<()> {
    let mut command = Command::new("iverilog");
    command.args(["-Wall", "-tnull", "-grelative-include"]);
    if files
        .iter()
        .any(|p| p.extension().is_some_and(|ext| ext == "sv"))
    {
        command.arg("-g2012");
    }
    if let Some(name) = top {
        command.args(["-s", name]);
    }
    checked(command.args(source_paths(files)?))
}

fn build(design: Design, program: bool) -> Result<()> {
    let main = &design.sources[0];
    let sources = source_paths(&design.sources)?;
    let project = board_project(&sources[0])?;
    let build_dir = main.with_file_name("build");
    fs::create_dir_all(&build_dir).with_context(|| format!("creating {}", build_dir.display()))?;
    let output = build_dir
        .join(main.file_name().context("expected a source filename")?)
        .with_extension("fs");
    // Stage files beside the output so a failed or concurrent build cannot publish a partial bitstream.
    let scratch = tempfile::Builder::new()
        .prefix(".tang-")
        .tempdir_in(&build_dir)?;
    let sidecar = main.with_extension("cst");
    let constraints = match design.cst {
        Some(path) => path,
        None if sidecar.try_exists()? => sidecar,
        None => board_pins(project, scratch.path())?,
    };
    ensure!(
        constraints.is_file(),
        "pin constraints not found: {}",
        constraints.display()
    );
    let synth = scratch.path().join("synth.json");
    let routed = scratch.path().join("routed.json");
    let packed = scratch.path().join("bitstream.fs");

    eprintln!("Synthesizing {}", main.display());
    checked(
        Command::new("yosys")
            .args(["-Q", "-q", "-p"])
            .arg(format!("synth_gowin -top {}", design.top))
            .arg("-o")
            .arg(&synth)
            .args(&sources),
    )?;

    eprintln!("Placing and routing at 27 MHz");
    let mut pins = OsString::from("cst=");
    pins.push(constraints);
    checked(
        Command::new("nextpnr-himbaechel")
            .args(["--quiet", "--device", DEVICE, "--vopt"])
            .arg(format!("family={FAMILY}"))
            .arg("--vopt")
            .arg(pins)
            .args(["--freq", "27", "--json"])
            .arg(synth)
            .arg("--write")
            .arg(&routed),
    )?;

    eprintln!("Packing {}", output.display());
    let mut packer = match project {
        Some(root) if root.join("pyproject.toml").try_exists()? => {
            let mut uv = Command::new("uv");
            uv.args(["run", "--locked", "--project"]).arg(root);
            uv.args(["python", "-m", "apycula.gowin_pack"]);
            uv
        }
        _ => Command::new("gowin_pack"),
    };
    checked(packer.args(["-d", FAMILY, "-o"]).arg(&packed).arg(routed))?;
    // Load this build's own bitstream even if another build has the same output name.
    let upload = if program { load(&packed) } else { Ok(()) };
    fs::rename(packed, &output).with_context(|| format!("writing {}", output.display()))?;
    upload
}

fn programmer_missing(output: &Output) -> bool {
    !output.status.success()
        && String::from_utf8_lossy(&output.stderr)
            .contains("unable to open ftdi device: -3 (device not found)")
}

fn reattach_wsl() -> Result<()> {
    // usbipd requires an already-shared device and a unique match for this ID.
    let args = ["attach", "--wsl", "--hardware-id", "0403:6010"];
    let status = match Command::new("usbipd.exe").args(args).status() {
        Err(err) if err.kind() == io::ErrorKind::NotFound => {
            Command::new("/mnt/c/Program Files/usbipd-win/usbipd.exe")
                .args(args)
                .status()
        }
        other => other,
    }
    .context("could not start usbipd-win; check that it is installed on Windows")?;
    ensure!(
        status.success(),
        "USB reconnect failed. Run 'usbipd list' in PowerShell. If multiple adapters match, attach the Tang by its BUSID."
    );
    Ok(())
}

fn load(bitstream: &Path) -> Result<()> {
    ensure!(
        bitstream.extension().is_some_and(|ext| ext == "fs"),
        "expected a .fs bitstream"
    );
    let file = bitstream
        .canonicalize()
        .with_context(|| format!("opening {}", bitstream.display()))?;
    ensure!(file.is_file(), "{} is not a file", file.display());
    let args = ["-b", "tangnano20k", "--write-sram"];
    eprintln!("Loading {} into SRAM", bitstream.display());
    let mut loader = Command::new("openFPGALoader");
    loader.args(args).arg(&file);
    let mut result = loader.output().context("could not start openFPGALoader")?;
    if programmer_missing(&result) && env::var_os("WSL_DISTRO_NAME").is_some() {
        eprintln!("Reconnecting the Tang Nano to WSL...");
        reattach_wsl()?;
        // Windows may finish attaching just before Linux creates the USB device.
        for _ in 0..12 {
            thread::sleep(Duration::from_millis(250));
            result = loader.output().context("could not retry openFPGALoader")?;
            if !programmer_missing(&result) {
                break;
            }
        }
    }
    let errors = String::from_utf8_lossy(&result.stderr);
    if !result.status.success() && errors.contains("usb_open() failed") {
        // sudo's PATH does not normally include OSS CAD Suite.
        let path = env::var_os("PATH").unwrap_or_default();
        let loader = env::split_paths(&path)
            .map(|dir| dir.join("openFPGALoader"))
            .find(|p| {
                p.metadata()
                    .is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
            })
            .context("could not locate openFPGALoader in PATH")?
            .canonicalize()?;
        eprintln!("USB access needs permission. Running the loader with sudo.");
        return checked(
            Command::new("sudo")
                .arg("--")
                .arg(loader)
                .args(args)
                .arg(file),
        );
    }
    io::stdout().write_all(&result.stdout)?;
    io::stderr().write_all(&result.stderr)?;
    if !result.status.success() && errors.contains("device not found") {
        bail!("Tang Nano 20K not found. If using WSL, attach the board with usbipd first.");
    }
    ensure!(
        result.status.success(),
        "openFPGALoader failed ({})",
        result.status
    );
    Ok(())
}

fn main() -> Result<()> {
    match Cli::parse().action {
        Action::Check { sources, top } => check(&sources, top.as_deref()),
        Action::Build(design) => build(design, false),
        Action::Load { bitstream } => {
            let built = Path::new("build").join(&bitstream);
            if bitstream.parent() == Some(Path::new("")) && built.try_exists()? {
                load(&built)
            } else {
                load(&bitstream)
            }
        }
        Action::Run(design) => build(design, true),
    }
}
