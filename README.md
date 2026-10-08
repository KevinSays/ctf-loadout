# ctf-loadout

One script that gears up a Linux machine for the team's two training tracks:

- **[CTF-training](https://github.com/joshbrunty/CTF-training)**: the 8-module CTF course (crypto, web, networking, forensics, reverse engineering)
- **[OpenCyberRange](https://github.com/syntaxoverride/opencyberrange)**: the hands-on range and its student workbook

It detects your distro, shows you exactly what it will install, asks before changing anything, installs it with the right package manager, and downloads both course repos.

## The course repos

ctf-loadout's tool list comes straight from these two repos: every tool the lessons and workbook use. **Get both**, since they hold the actual lessons, labs and challenge files. ctf-loadout only installs the tools.

| Repo | What's in it | Link |
|---|---|---|
| **CTF-training** | The 8-module CTF course by Dr. Josh Brunty (Marshall University): lessons, slides and challenge files | https://github.com/joshbrunty/CTF-training |
| **OpenCyberRange** | The self-hosted cyber range, plus the student workbook (`Workbook/`) that walks through each lab | https://github.com/syntaxoverride/opencyberrange |

`loadout.sh` downloads both for you. To grab them yourself instead:

```bash
git clone https://github.com/joshbrunty/CTF-training.git
git clone https://github.com/syntaxoverride/opencyberrange.git
```

If you already have them, point ctf-loadout at their folder with `--dir=PATH` so it doesn't download them again.

All credit for the course content goes to these projects' authors. Check each repo for its license and terms of use.

## Quick start

```bash
git clone https://github.com/KevinSays/ctf-loadout.git
cd ctf-loadout
./loadout.sh --dry-run   # preview: changes nothing
./loadout.sh             # install, asking before each step
```

Run it as your normal user, **not** with `sudo`. It asks for your password when it needs it.

The recommended setup is a **Kali Linux VM**, where every tool installs from Kali's own repos. The course assumes Kali, and a VM keeps untrusted CTF files away from your real machine.

## Options

| Option | What it does |
|---|---|
| `--dry-run` | Show the plan, the notes and the run commands. Install nothing. |
| `--yes` | Answer yes to every prompt |
| `--sections=core,ctf,range` | Only set up some sections (`core` is always included) |
| `--dir=PATH` | Where to download the course repos (default: this folder) |
| `--help` | Show usage |

## What it sets up

| Section | Includes |
|---|---|
| `core` | git, curl, Python 3, pip, pipx, file, xxd, binutils |
| `ctf` | Wireshark/tshark/tcpdump, Burp Suite, sqlmap, John, hashcat, hashid, rockyou.txt, exiftool, binwalk, foremost, Sleuth Kit, Autopsy, Volatility 3, Ghidra, gdb, plus the CTF-training repo |
| `range` | WireGuard, nmap, smbclient/rpcclient, enum4linux, CrackMapExec, Hydra, FreeRDP, Evil-WinRM, MySQL client, ldapsearch, ssh, netcat, gobuster, dirb, whatweb, searchsploit, plus the opencyberrange repo |

When it finishes, it prints **Things to know** and **How to run these**, with commands for each tool.

## Supported distros

| Family | Distros | Notes |
|---|---|---|
| apt | **Kali** (recommended), Debian, Ubuntu | Some tools (Burp, Ghidra, enum4linux, CrackMapExec, Evil-WinRM, searchsploit) are Kali-only and show as manual steps elsewhere |
| pacman | Arch, Omarchy, Manjaro | AUR packages need `yay` or `paru` |
| dnf | Fedora | Several tools aren't packaged and show as manual steps |

Package names are checked against the Kali rolling, Debian trixie, Ubuntu noble, Fedora 43 and Arch/AUR package indexes.

## Good to know

- **RangeBox needs no installs.** OpenCyberRange has an in-browser desktop with every range tool already installed and no VPN needed. The `range` section is only for working from your own machine.
- **Volatility 3** isn't in Kali's repos, so the course's `sudo apt install volatility3` fails. ctf-loadout installs it with `pipx`. The command is `vol`.
- **FreeRDP 3** names its command `xfreerdp3`. Use it wherever the workbook says `xfreerdp`.
- **On Arch,** CrackMapExec is replaced by its successor NetExec: run `nxc` with the same syntax.
- **hashcat in a VM** has no GPU. Add `--force` if it reports `No devices found`.
- Only point the range tools at your own lab targets on the range.
- Run it before practice. Venue Wi-Fi can be slow, and the two course repos total about 500 MB.
