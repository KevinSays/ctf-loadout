#!/usr/bin/env bash
#
# ctf-loadout: detect the distro, show what will be installed for the
# CTF-training course and the OpenCyberRange workbook, then install it with the
# right package manager and download both lab repos.
#
# Usage:
#   ./loadout.sh                  interactive (asks before each step)
#   ./loadout.sh --dry-run        show the plan, change nothing
#   ./loadout.sh --yes            answer yes to every prompt
#   ./loadout.sh --sections=core,ctf
#   ./loadout.sh --dir=~/labs     where to put the lab repos
#                                 (default: the folder this script is in)
#
# Sections: core ctf range
#
# Run as your normal user (not root); the script calls sudo when it needs to.
# Safe to re-run: anything already installed is skipped.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALL_SECTIONS=(core ctf range)

DRY_RUN=0
ASSUME_YES=0
SECTIONS_ARG=""
LABS_DIR="$SCRIPT_DIR"

for arg in "$@"; do
    case "$arg" in
        --dry-run)    DRY_RUN=1 ;;
        -y|--yes)     ASSUME_YES=1 ;;
        --sections=*) SECTIONS_ARG="${arg#*=}" ;;
        --sections)   echo "Use --sections=core,ctf,..." >&2; exit 1 ;;
        --dir=*)      LABS_DIR="${arg#*=}"; LABS_DIR="${LABS_DIR/#\~/$HOME}" ;;
        -h|--help)    awk 'NR>1 && !/^#/ {exit} NR>1 {sub(/^# ?/, ""); print}' "$0"; exit 0 ;;
        *)            echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done
LABS_DIR="$(realpath -m "$LABS_DIR")"

# --- output helpers ---------------------------------------------------------

if [[ -t 1 ]]; then
    B=$'\e[1m'; DIM=$'\e[2m'; R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; N=$'\e[0m'
else
    B=""; DIM=""; R=""; G=""; Y=""; C=""; N=""
fi

info()  { echo "${C}[*]${N} $*"; }
ok()    { echo "${G}[+]${N} $*"; }
warn()  { echo "${Y}[!]${N} $*"; }
fail()  { echo "${R}[x]${N} $*"; }
header(){ echo; echo "${B}== $* ==${N}"; }

confirm() {
    # confirm "question" -> 0 for yes
    (( ASSUME_YES )) && return 0
    local reply
    read -r -p "$1 [y/N] " reply
    [[ "$reply" =~ ^[Yy] ]]
}

run() {
    # Echo and run a command, or only echo it in dry-run mode.
    if (( DRY_RUN )); then
        echo "    ${DIM}would run:${N} $*"
        return 0
    fi
    "$@"
}

# --- distro detection -------------------------------------------------------

if [[ $EUID -eq 0 ]]; then
    fail "Run this as your normal user; it will use sudo when needed."
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    fail "Cannot read /etc/os-release; unknown distro."
    exit 1
fi
# shellcheck disable=SC1091
. /etc/os-release
DISTRO_ID="${ID:-unknown}"
DISTRO_LIKE="${ID_LIKE:-}"
DISTRO_NAME="${PRETTY_NAME:-$DISTRO_ID}"

FAMILY=""
case " $DISTRO_ID $DISTRO_LIKE " in
    *" kali "*|*" debian "*|*" ubuntu "*) FAMILY=apt ;;
    *" arch "*)                           FAMILY=pacman ;;
    *" fedora "*|*" rhel "*)              FAMILY=dnf ;;
esac

if [[ -z "$FAMILY" ]]; then
    fail "Unsupported distro: $DISTRO_NAME (ID=$DISTRO_ID, ID_LIKE=$DISTRO_LIKE)"
    echo "    Supported: Kali/Debian/Ubuntu (apt), Arch/Omarchy/Manjaro (pacman), Fedora (dnf)."
    exit 1
fi

IS_KALI=0
[[ "$DISTRO_ID" == "kali" ]] && IS_KALI=1

IS_ARM=0
[[ "$(uname -m)" == aarch64 || "$(uname -m)" == arm64 ]] && IS_ARM=1

AUR_HELPER=""
if [[ "$FAMILY" == pacman ]]; then
    for h in yay paru; do
        command -v "$h" >/dev/null 2>&1 && { AUR_HELPER="$h"; break; }
    done
fi

# --- package catalogue ------------------------------------------------------
#
# section|tool|apt package|pacman package|dnf package|what it's for
#
#   pkg          install from the distro repos
#   aur:pkg      Arch: install from the AUR (needs yay or paru)
#   kali:pkg     apt: only in Kali's repos (manual step elsewhere)
#   kaliopt:pkg  apt: install on Kali, skip elsewhere (handled by a later step)
#   arm:pkg      apt: only needed on ARM machines
#   pipx:pkg:cmd install with pipx as your user (cmd = the command it provides)
#   .            nothing to install on this distro
#   -            not packaged; listed as a manual step instead
#
# Names checked against the Kali rolling, Debian trixie, Ubuntu noble,
# Fedora 43 and Arch/AUR package indexes.

CATALOGUE=$(cat <<'EOF'
core|git|git|git|git|Download and update the lab repos
core|curl|curl|curl|curl|Downloads, HTTP requests (both courses)
core|python3|python3|python|python3|Scripting for every module
core|pip|python3-pip|python-pip|python3-pip|Python packages
core|pipx|pipx|python-pipx|pipx|Installs Python tools (Volatility 3)
core|venv|python3-venv|.|.|Isolated Python environments
core|file|file|file|file|Identify file types
core|xxd|xxd|tinyxxd|vim-common|Hex dump / reverse hex
core|binutils|binutils|binutils|binutils|objdump, strings, readelf
ctf|wireshark|wireshark|wireshark-qt|wireshark|Packet analysis GUI (Day 5)
ctf|tshark|tshark|wireshark-cli|wireshark-cli|Packet analysis CLI (Day 5)
ctf|tcpdump|tcpdump|tcpdump|tcpdump|Read/capture packets (Day 5)
ctf|burpsuite|kali:burpsuite|aur:burpsuite|-|Web proxy (Day 4)
ctf|sqlmap|sqlmap|sqlmap|-|SQL injection testing (Day 4)
ctf|john|john|john|john|Hash cracking, CPU-friendly (Day 3)
ctf|hashcat|hashcat|hashcat|hashcat|Hash cracking, GPU (Day 3)
ctf|pocl|pocl-opencl-icd|pocl|pocl|CPU OpenCL so hashcat runs in a VM
ctf|hashid|hashid|aur:hashid|-|Identify hash types (Day 3)
ctf|rockyou|kaliopt:wordlists|.|.|rockyou.txt and other wordlists
ctf|exiftool|libimage-exiftool-perl|perl-image-exiftool|perl-Image-ExifTool|File metadata (Day 6)
ctf|binwalk|binwalk|binwalk|binwalk|Carve embedded files (Day 6)
ctf|foremost|foremost|aur:foremost|foremost|File carving (Day 6)
ctf|sleuthkit|sleuthkit|sleuthkit|sleuthkit|Disk images: fls, icat (Day 6)
ctf|autopsy|autopsy|aur:autopsy|-|Forensics GUI (Day 6)
ctf|volatility3|pipx:volatility3:vol|pipx:volatility3:vol|pipx:volatility3:vol|Memory forensics (Day 6, optional)
ctf|ghidra|kali:ghidra|ghidra|-|Decompiler (Day 7)
ctf|gdb|gdb|gdb|gdb|Debugger (Day 7)
ctf|x86 objdump|arm:binutils-x86-64-linux-gnu|.|.|Read x86 binaries on ARM (Day 7)
range|wireguard|wireguard-tools|wireguard-tools|wireguard-tools|VPN into the range
range|nmap|nmap|nmap|nmap|Scanning and NSE scripts (CH01+)
range|smbclient|smbclient|smbclient|samba-client|SMB shares + rpcclient (CH02)
range|enum4linux|kali:enum4linux|aur:enum4linux|-|SMB/RPC enumeration (CH02)
range|crackmapexec|kali:crackmapexec|aur:netexec|-|Credential testing (CH03, CH08)
range|hydra|hydra|hydra|hydra|Login brute force (CH03, LIN02)
range|xfreerdp|freerdp3-x11|freerdp|freerdp|RDP client (CH04)
range|evil-winrm|kali:evil-winrm|-|-|WinRM shell (CH05)
range|mysql|default-mysql-client|mariadb-clients|mariadb|MySQL/MariaDB client (WEB02)
range|ldapsearch|ldap-utils|openldap|openldap-clients|LDAP queries (CH07)
range|ssh|openssh-client|openssh|openssh-clients|SSH labs (LIN02, LIN03)
range|nc|netcat-openbsd|openbsd-netcat|nmap-ncat|netcat: banner grabbing, raw connections
range|tshark|tshark|wireshark-cli|wireshark-cli|PCAP forensics (NET02)
range|gobuster|gobuster|gobuster|gobuster|Directory discovery (WEB01)
range|dirb|dirb|aur:dirb|-|Directory discovery + wordlists (WEB01)
range|whatweb|whatweb|aur:whatweb|whatweb|Web fingerprinting (WEB01)
range|searchsploit|kali:exploitdb|aur:exploitdb|-|Exploit-DB search (CH01)
EOF
)

# section|github owner/repo|folder name (cloned into LABS_DIR)
LAB_REPOS=$(cat <<'EOF'
ctf|joshbrunty/CTF-training|CTF-training
range|syntaxoverride/opencyberrange|opencyberrange
EOF
)

section_title() {
    case "$1" in
        core)  echo "Core tools (needed by everything)" ;;
        ctf)   echo "CTF-training modules 1-8" ;;
        range) echo "OpenCyberRange workbook (when working from your own machine)" ;;
    esac
}

# Resolve a catalogue entry for this distro.
# Prints "repo <pkg>", "aur <pkg>", "pipx <pkg> <cmd>", "skip", or "manual".
resolve() {
    local apt_p="$1" pac_p="$2" dnf_p="$3" p rest
    case "$FAMILY" in
        apt)    p="$apt_p" ;;
        pacman) p="$pac_p" ;;
        dnf)    p="$dnf_p" ;;
    esac
    case "$p" in
        .)      echo "skip" ;;
        -)      echo "manual" ;;
        aur:*)  [[ -n "$AUR_HELPER" ]] && echo "aur ${p#aur:}" || echo "manual" ;;
        kali:*) (( IS_KALI )) && echo "repo ${p#kali:}" || echo "manual" ;;
        kaliopt:*) (( IS_KALI )) && echo "repo ${p#kaliopt:}" || echo "skip" ;;
        arm:*)  (( IS_ARM )) && echo "repo ${p#arm:}" || echo "skip" ;;
        pipx:*) rest="${p#pipx:}"; echo "pipx ${rest%%:*} ${rest#*:}" ;;
        *)      echo "repo $p" ;;
    esac
}

is_installed() {
    case "$FAMILY" in
        apt)    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed" ;;
        pacman) pacman -Qq "$1" >/dev/null 2>&1 ;;
        dnf)    rpm -q "$1" >/dev/null 2>&1 ;;
    esac
}

# A tool counts as present if its command is already on PATH (e.g. from mise or pipx).
has_cmd() {
    [[ "$1" != *" "* ]] && command -v "$1" >/dev/null 2>&1
}

# --- choose sections --------------------------------------------------------

header "ctf-loadout"
info "Distro:          ${B}$DISTRO_NAME${N}"
info "Package manager: ${B}$FAMILY${N}${AUR_HELPER:+ (AUR via $AUR_HELPER)}"
info "Lab folder:      ${B}${LABS_DIR/#$HOME/\~}${N}"
(( DRY_RUN )) && warn "Dry run: nothing will be installed."
[[ "$FAMILY" == pacman && -z "$AUR_HELPER" ]] && \
    warn "No yay/paru found; AUR packages will be listed as manual steps."

declare -A WANT=()
if [[ -n "$SECTIONS_ARG" ]]; then
    IFS=',' read -r -a picked <<< "$SECTIONS_ARG"
    for s in "${picked[@]}"; do
        [[ " ${ALL_SECTIONS[*]} " == *" $s "* ]] || { fail "Unknown section: $s"; exit 1; }
        WANT[$s]=1
    done
    WANT[core]=1
else
    for s in "${ALL_SECTIONS[@]}"; do WANT[$s]=1; done
fi

# Lab repos the chosen sections need.
NEEDED_REPOS=()
while IFS='|' read -r sec repo dir; do
    [[ -n "${WANT[$sec]:-}" ]] && NEEDED_REPOS+=("$repo|$dir")
done <<< "$LAB_REPOS"

# --- things to know (shown after the plan and again in the summary) ---------

print_notes() {
    echo "${B}Things to know:${N}"
    if [[ -n "${WANT[ctf]:-}" ]]; then
        echo "  - Open unknown CTF files (binaries, disk images, memory dumps) only inside your VM."
        if [[ ! -f /usr/share/wordlists/rockyou.txt && ! -f /usr/share/wordlists/rockyou.txt.gz ]]; then
            echo "  - rockyou.txt lives in ~/wordlists/ here, so swap that in wherever the course"
            echo "    uses /usr/share/wordlists/rockyou.txt."
        fi
        echo "  - hashcat in a VM has no GPU: add --force if it reports 'No devices found'."
        echo "  - Volatility 3 isn't in Kali's repos, so the course's 'apt install volatility3'"
        echo "    fails. This script installs it with pipx instead; the command is 'vol'."
        if [[ "$FAMILY" == apt ]]; then
            echo "  - The apt 'autopsy' is the older web version: run 'sudo autopsy', then open"
            echo "    http://localhost:9999/autopsy in a browser."
        fi
        (( IS_ARM )) && echo "  - ARM machine: use x86_64-linux-gnu-objdump for the Day 7 binary."
    fi
    if [[ -n "${WANT[range]:-}" ]]; then
        echo "  - You can skip the range tools entirely by working in RangeBox, the in-browser"
        echo "    desktop on the range: it has them all and needs no VPN."
        echo "  - Only point the range tools at your own lab targets on the range."
        echo "  - FreeRDP 3 names its command xfreerdp3; use it wherever the workbook says xfreerdp."
        if [[ "$FAMILY" == pacman ]]; then
            echo "  - Arch has NetExec instead of CrackMapExec: same syntax, run 'nxc' where the"
            echo "    workbook says 'crackmapexec'."
        fi
        if ! (( IS_KALI )); then
            echo "  - The workbook's wordlist paths (/usr/share/wordlists/...) are Kali's. On this"
            echo "    distro, use RangeBox or a Kali VM for those steps."
        fi
    fi
    echo "  - Group changes (wireshark) take effect after you log out and back in."
    echo "  - Run this script as your normal user, not with sudo; it asks for sudo when needed."
    echo "  - Download everything before class, since venue Wi-Fi may be slow."
    echo
}

# --- how to run (shown at the end of the summary) ----------------------------

print_howto() {
    local d="${LABS_DIR/#$HOME/\~}" rockyou="/usr/share/wordlists/rockyou.txt"
    [[ ! -f "$rockyou" && -f "$HOME/wordlists/rockyou.txt" ]] && rockyou="~/wordlists/rockyou.txt"
    howto() {
        # Command, then its description; long commands get the description on the next line.
        if [[ -z "$2" ]]; then
            printf "    %s\n" "$1"
        elif (( ${#1} > 36 )); then
            printf "    %s\n    %-36s ${DIM}%s${N}\n" "$1" "" "$2"
        else
            printf "    %-36s ${DIM}%s${N}\n" "$1" "$2"
        fi
    }

    echo "${B}How to run these:${N}"
    if [[ -n "${WANT[ctf]:-}" ]]; then
        echo "  ${B}CTF-training${N} (lessons: $d/CTF-training/0*/README.md, slides in PowerPoints/)"
        howto "https://gchq.github.io/CyberChef/" "CyberChef, in your browser"
        howto "wireshark <file.pcap>" "open a capture (Day 5)"
        howto "tcpdump -r <file.pcap> -A" "read a capture in the terminal"
        howto "burpsuite" "web proxy (Day 4)"
        howto "john --format=raw-md5 --wordlist=$rockyou hash.txt" ""
        howto "hashcat -m 0 -a 0 hash.txt $rockyou" "add --force in a VM"
        howto "exiftool <file> / binwalk -e <file>" "metadata / carving (Day 6)"
        if [[ "$FAMILY" == apt ]]; then
            howto "sudo autopsy" "then open http://localhost:9999/autopsy (Day 6)"
        else
            howto "autopsy" "disk image GUI (Day 6)"
        fi
        howto "vol -f memory.raw windows.pslist" "Volatility 3 (Day 6 optional)"
        howto "ghidra" "decompiler (Day 7)"
        echo
    fi
    if [[ -n "${WANT[range]:-}" ]]; then
        echo "  ${B}OpenCyberRange${N} (workbook: $d/opencyberrange/Workbook/)"
        howto "https://<range-server-ip>" "sign up, launch a lab, or open RangeBox"
        howto "sudo wg-quick up ./<your-config>.conf" "connect your own machine to the range"
        howto "sudo wg-quick down ./<your-config>.conf" "disconnect"
        howto "nmap -sV <target>" "service scan (CH01)"
        howto "smbclient -L //<target> -N" "list SMB shares (CH02)"
        howto "ldapsearch -x -H ldap://<target> -s base" "LDAP root DSE (CH07)"
        howto "xfreerdp3 /v:<target> /u:<user>" "RDP session (CH04)"
        echo
    fi
}

# --- show the plan ----------------------------------------------------------

REPO_PKGS=()
AUR_PKGS=()
PIPX_PKGS=()
MANUAL=()
declare -A QUEUED=()

header "Plan"
for s in "${ALL_SECTIONS[@]}"; do
    [[ -n "${WANT[$s]:-}" ]] || continue
    echo
    echo "${B}[$s] $(section_title "$s")${N}"
    while IFS='|' read -r sec repo dir; do
        [[ "$sec" == "$s" ]] || continue
        if [[ -d "$LABS_DIR/$dir/.git" ]]; then
            status="${G}downloaded${N}"
        else
            status="${C}clone${N} github.com/$repo"
        fi
        printf "  %-16s %-40s %s\n" "$dir" "Lab repo" "$status"
    done <<< "$LAB_REPOS"
    while IFS='|' read -r sec tool apt_p pac_p dnf_p desc; do
        [[ "$sec" == "$s" ]] || continue
        read -r how pkg cmd <<< "$(resolve "$apt_p" "$pac_p" "$dnf_p")"
        case "$how" in
            skip)
                if has_cmd "$tool"; then status="${G}installed${N}"; else status="${DIM}n/a${N}"; fi ;;
            manual)
                status="${Y}manual${N}"; MANUAL+=("$tool: $desc") ;;
            pipx)
                if has_cmd "$cmd"; then
                    status="${G}installed${N}"
                else
                    status="${C}install${N} $pkg${DIM} (pipx)${N}"
                    [[ -z "${QUEUED[pipx:$pkg]:-}" ]] && { QUEUED[pipx:$pkg]=1; PIPX_PKGS+=("$pkg"); }
                fi ;;
            repo|aur)
                if is_installed "$pkg" || has_cmd "$tool"; then
                    status="${G}installed${N}"
                else
                    status="${C}install${N} $pkg${DIM}$([[ $how == aur ]] && echo ' (AUR)')${N}"
                    # The same package can appear in several sections; queue it once.
                    if [[ -z "${QUEUED[$pkg]:-}" ]]; then
                        QUEUED[$pkg]=1
                        [[ $how == repo ]] && REPO_PKGS+=("$pkg") || AUR_PKGS+=("$pkg")
                    fi
                fi ;;
        esac
        printf "  %-16s %-40s %s\n" "$tool" "$desc" "$status"
    done <<< "$CATALOGUE"
done

echo
info "To install from repos: ${#REPO_PKGS[@]} package(s)"
info "To install from AUR:   ${#AUR_PKGS[@]} package(s)"
info "To install with pipx:  ${#PIPX_PKGS[@]} package(s)"
info "Manual steps:          ${#MANUAL[@]}"
echo
print_notes

if ! (( DRY_RUN )); then
    confirm "Proceed with installation?" || { info "Nothing changed."; exit 0; }
fi

# --- install ----------------------------------------------------------------

FAILED=()

refresh_index() {
    case "$FAMILY" in
        apt)    run sudo apt-get update ;;
        pacman) run sudo pacman -Sy ;;
        dnf)    run sudo dnf makecache ;;
    esac
}

install_repo_pkg() {
    case "$FAMILY" in
        apt)    run sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$1" ;;
        pacman) run sudo pacman -S --needed --noconfirm "$1" ;;
        dnf)    run sudo dnf install -y "$1" ;;
    esac
}

install_aur_pkg() {
    run "$AUR_HELPER" -S --needed --noconfirm "$1"
}

if (( ${#REPO_PKGS[@]} + ${#AUR_PKGS[@]} )); then
    header "Installing packages"
    (( DRY_RUN )) || sudo -v || { fail "sudo is required."; exit 1; }
    # On Arch, -Sy without -u risks a partial upgrade; do a full upgrade instead.
    if [[ "$FAMILY" == pacman ]]; then
        if confirm "Arch needs a full system upgrade (pacman -Syu) before installing. Run it?"; then
            run sudo pacman -Syu --noconfirm
        else
            warn "Skipping upgrade; installs may fail on out-of-date mirrors."
        fi
    else
        refresh_index
    fi

    # One package at a time so a single missing name doesn't block the rest.
    for p in "${REPO_PKGS[@]}"; do
        info "Installing $p"
        install_repo_pkg "$p" || { fail "$p failed"; FAILED+=("$p"); }
    done
    for p in "${AUR_PKGS[@]}"; do
        info "Installing $p (AUR, may take a while)"
        install_aur_pkg "$p" || { fail "$p failed"; FAILED+=("$p (AUR)"); }
    done
fi

if (( ${#PIPX_PKGS[@]} )); then
    header "Installing Python tools"
    for p in "${PIPX_PKGS[@]}"; do
        info "Installing $p with pipx"
        run pipx install "$p" || { fail "$p failed"; FAILED+=("$p (pipx)"); }
    done
    # Make sure ~/.local/bin (where pipx puts commands) is on PATH.
    run pipx ensurepath >/dev/null
fi

# --- post-install steps -----------------------------------------------------

header "Post-install steps"

if (( ${#NEEDED_REPOS[@]} )); then
    info "Lab repos go in ${LABS_DIR/#$HOME/\~}"
    run mkdir -p "$LABS_DIR"
    EXISTING=()
    for entry in "${NEEDED_REPOS[@]}"; do
        repo="${entry%%|*}" dir="$LABS_DIR/${entry#*|}"
        if [[ -d "$dir/.git" ]]; then
            EXISTING+=("$dir")
        elif [[ -e "$dir" ]]; then
            warn "$dir exists but isn't a git repo; leaving it alone."
        else
            info "Cloning $repo"
            run git clone "https://github.com/$repo.git" "$dir" || FAILED+=("$repo clone")
        fi
    done
    if (( ${#EXISTING[@]} )) && confirm "Update ${#EXISTING[@]} already-downloaded lab repo(s) with git pull?"; then
        for dir in "${EXISTING[@]}"; do
            run git -C "$dir" pull --ff-only || FAILED+=("$(basename "$dir") git pull")
        done
    fi
fi

if [[ -n "${WANT[ctf]:-}" || -n "${WANT[range]:-}" ]]; then
    # rockyou.txt: Kali ships it gzipped; other distros need a download.
    if [[ -f /usr/share/wordlists/rockyou.txt ]]; then
        ok "rockyou.txt present at /usr/share/wordlists/rockyou.txt"
    elif [[ -f /usr/share/wordlists/rockyou.txt.gz ]]; then
        info "Decompressing rockyou.txt.gz"
        run sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz
    elif [[ -f "$HOME/wordlists/rockyou.txt" ]]; then
        ok "rockyou.txt present at ~/wordlists/rockyou.txt"
    elif confirm "Download rockyou.txt (~134 MB) to ~/wordlists?"; then
        run mkdir -p "$HOME/wordlists"
        run curl -fL -o "$HOME/wordlists/rockyou.txt" \
            "https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt" \
            || FAILED+=("rockyou.txt download")
    fi

    # Let the user capture with Wireshark without root.
    if getent group wireshark >/dev/null && ! id -nG | grep -qw wireshark; then
        if confirm "Add $USER to the 'wireshark' group (capture without sudo)?"; then
            run sudo usermod -aG wireshark "$USER" && warn "Log out and back in for the group change."
        fi
    fi
fi

# --- summary ----------------------------------------------------------------

header "Summary"

if (( ${#MANUAL[@]} )); then
    echo "${Y}Manual steps for $DISTRO_NAME:${N}"
    for m in "${MANUAL[@]}"; do echo "  - $m"; done
    case "$FAMILY" in
        apt|dnf) echo "  Tip: the Kali-only tools are easiest in a Kali VM or RangeBox. Burp Suite (portswigger.net)"
                 echo "  and Ghidra (ghidra-sre.org) have direct downloads." ;;
        pacman)  [[ -z "$AUR_HELPER" ]] && echo "  Tip: install yay (https://github.com/Jguer/yay) and re-run to get the AUR packages."
                 echo "  Tip: evil-winrm installs with 'gem install evil-winrm', or use RangeBox." ;;
    esac
    echo
fi

echo "Also needed, outside this machine:"
echo "  - A Kali Linux VM (VirtualBox/VMware) for running untrusted CTF files"
echo "  - An OpenCyberRange account, plus your WireGuard config from the range web UI"
echo "    (or use RangeBox in the browser instead)"
echo

print_notes
print_howto

if (( ${#FAILED[@]} )); then
    fail "Failed:"
    for f in "${FAILED[@]}"; do echo "  - $f"; done
    exit 1
fi
(( DRY_RUN )) && ok "Dry run complete." || ok "All done."
