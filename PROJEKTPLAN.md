Appliance OS for Home Servers – Project Plan
Working title: HomeAppliance OS (feel free to change; avoid using "Debian" in the name – the trademark is protected).
0. Key adjustments to the approach
Your plan	Recommendation	Reason
Cubic	Debian live-build (`lb`)	Cubic is manual/GUI-based and not reproducible. `live-build` is Debian’s official ISO tool; it can be run in a CI environment (GitHub Actions) and produces identical ISOs every time. Cubic is fine for quick prototypes.
Archiso	Discard	Archiso is specific to Arch and not suitable for a Debian-based system.
Install CasaOS in a chroot	Install on first boot	The CasaOS installer requires a running `systemd`, Docker, and network access—none of which are available during the ISO build process.
Pre-load Docker images	Download on first boot	Applications like Immich, n8n, and Paperless add up to several gigabytes. An offline version could be released as "v2."
CasaOS as a fixed foundation	Verify current status	Development of CasaOS has been slow; test it against Debian 13 ("trixie") before committing to it. Keep Portainer or Dockge as a backup plan.
Immich	Optional; include a resource warning	Requires significant RAM and CPU (due to machine learning). Older laptops may become overloaded—the setup wizard should provide a warning. 1. Architecture
```
Debian 13 (trixie) ──► live-build ──► hybrid ISO (BIOS + UEFI)
                                          │
                       Calamares installer (server mode)
                                          │
                       Installed system: Docker, Tailscale, wizard, monitor
                                          │
                  first-boot.service ──► CasaOS + selected containers
                                          │
                  Welcome Wizard (CustomTkinter) ──► compose profiles
```
Design principles:
Idempotent: `first-boot` can be re-run without causing issues.
Service-specific components (such as Docker Compose profiles) are located in `/opt/applianceos/stacks/` – the wizard simply enables or disables these profiles.
Headless-first: Many servers lack a display. The wizard will also be available as a web interface (Phase 4); the CustomTkinter application is intended for machines with a display.
Secure defaults: Unique passwords are generated upon first boot; SSH key-based authentication is recommended; no ports are exposed to the internet (via Tailscale).
2. Phases
Phase 1 – Build Pipeline (Weeks 1–2)
Repo + `scripts/build-iso.sh` (included).
Build in a VM (QEMU/VirtualBox), verify BIOS + UEFI support.
GitHub Actions to build an ISO on every tag.
Phase 2 – Installer (Weeks 2–3)
Calamares with a custom theme, simplified partitioning (single disk, ext4, optional separate data disk).
Hostname, user account, time zone (default: Europe/Stockholm).
Phase 3 – First-boot (Weeks 3–4)
`first-boot.sh` + systemd unit (next delivery).
Docker networking, CasaOS, n8n, etc.
Phase 4 – GUI (Weeks 4–6)
Wizard (for selecting services) + monitor (using `psutil`: CPU temp, disk, RAM, network).
Optional web-based interface (FastAPI) for headless operation.
Phase 5 – Testing & Hardware (Weeks 6–8)
Test on actual legacy laptops/mini-PCs (e.g., Wi-Fi firmware, sleep-on-lid-close).
Documentation, screenshots, demo video.
Phase 6 – Launch (Week 8+)
Beta release, Reddit, DistroWatch (see below).
3. License & Legal
Project-specific code: MIT or GPL-3.0.
Debian packages retain their original licenses; include non-free firmware only where necessary for drivers—clearly note this in the README.
Remove Debian logos/trademarks from the branding.
Publish SHA256 checksums and, ideally, a GPG signature for the ISO. 4. Launch & Marketing
Before launch
A functional ISO, a README with screenshots/GIFs, a short demo video (2–3 minutes), and a project page (GitHub Pages).
Include a solid "Getting started" guide, a clear list of what is included, and the minimum requirements (RAM, disk space).
Reddit
r/selfhosted: Read the rules first (they have had restrictions regarding self-promotion and AI-generated projects). Be honest: describe the problem, what the project is, what isn't working yet, and ask for feedback. Wait until there is something actually useful to show.
r/linux: Focus on the technical aspects of the build (live-build pipeline, design choices)—not on advertising.
r/unixporn: Only relevant if you are creating a visual theme or desktop environment—this community is about "ricing," not servers. Likely not relevant until the wizard/monitor looks polished.
Respond to comments promptly during the first 24 hours. Have issue templates ready.
DistroWatch
They have their own specific requirements (e.g., the distribution must be functional, downloadable, have a distinct identity/website, and demonstrate sustained activity over time). Review their current submission guidelines at distrowatch.com before applying—check them again when you are ready, as they are subject to change.
Prepare: a website, a download link, checksums, and release notes.
Other channels: Hacker News (Show HN), Lemmy (lemmy.world/c/selfhosted), YouTube creators in the homelab space, Mastodon, and Discord/Matrix for community building.
5. Next Deliverables
`first-boot.sh` + `first-boot.service`
Wizard + monitor (CustomTkinter + psutil)
Calamares theme and branding
GitHub Actions workflow
