# Appliance-Os

HomeAppliance OS 

Plug-and-play Linux for home servers, based on Debian 13. Install it on an old laptop or mini PC, select services via a wizard, and start self-hosting.

Status: early development – ​​no release yet.

What’s included
Docker + Compose, Tailscale
CasaOS (installed on first boot)
Optional stacks: n8n, Paperless-ngx, Immich
Welcome Wizard and System Monitor (Python/CustomTkinter)
Repo structure
. ├── README.md
├── LICENSE
├── PROJEKTPLAN.md
├── scripts/
│   ├── build-iso.sh          # builds an ISO using Debian live-build
│   ├── first-boot.sh         # runs once after installation
│   └── lib/                  # shared bash functions
├── overlay/                  # files copied directly into the system
│   ├── etc/systemd/system/
│   │   └── applianceos-first-boot.service
│   └── opt/applianceos/
│       └── stacks/           # docker-compose files per service
│           ├── n8n/
│           ├── paperless-ngx/
│           └── immich/
├── gui/
│   ├── wizard/               # First-Run Wizard
│   ├── monitor/              # psutil module
│   └── requirements.txt
├── calamares/                # branding + settings (theme, partitioning)
├── branding/                 # logo, backgrounds
├── docs/
│   ├── build.md
│   ├── install.md
│   └── hardware-compat.md
├── .github/
│   ├── workflows/build-iso.yml
│   └── ISSUE_TEMPLATE/
└── tests/                    # QEMU smoke tests for the ISO
Building the ISO

Requires a Debian host (or a Debian container/VM) with root access:

bash
sudo apt install live-build
sudo ./scripts/build-iso.sh
# result: ./work/*.iso

See docs/build.md for details.

License

MIT (for the project's own code). Included packages retain their own respective licenses.
