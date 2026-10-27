# DevOps Assignment 2 - Dockerized Diagnostic CLI

**Author:** Robert Olwoch

A Bash diagnostic tool packaged as a small Docker image. It shows system information, checks a host on the network and reports disk usage.

## Project structure

```
assignment-2/
├── README.md
├── app/
│   ├── diagnostic.sh      # the CLI (system / network / disk / help)
│   └── health-check.sh    # checks the tools the CLI needs are inside the image
├── Dockerfile
├── compose.yaml
├── .dockerignore
├── test.sh                # tests for the Docker image
└── grade.sh               # grader supplied with the assignment
```

## Requirements

- Linux with Docker Engine
- Docker Compose v2 (`docker compose version`)

## Setup

```bash
git clone https://github.com/Arkstones/devops-assignment-2.git
cd devops-assignment-2
chmod +x grade.sh test.sh app/*.sh
docker build -t diagnostic-tool .
```

## Usage

### Commands

| Command | What it does |
|---|---|
| `system` | Hostname, user, date/time, OS, kernel, architecture, uptime, CPU and memory |
| `network <host>` | Resolves the host, pings it and lists the network interfaces |
| `disk [path]` | Disk usage for a path (default `/`) |
| `help` | Shows the commands and usage |

### With Docker

```bash
docker run --rm diagnostic-tool help
docker run --rm diagnostic-tool system
docker run --rm diagnostic-tool network google.com
docker run --rm diagnostic-tool disk
docker run --rm diagnostic-tool          # no command shows the help
```

### With Docker Compose

```bash
docker compose build
docker compose run --rm diagnostic system
docker compose run --rm diagnostic network google.com
docker compose run --rm diagnostic disk
```

### Health check

```bash
docker run --rm --entrypoint /app/health-check.sh diagnostic-tool
```

### Without Docker

The script also runs directly on a Linux machine:

```bash
./app/diagnostic.sh system
```

## Exit codes

| Code | Meaning | Examples |
|---|---|---|
| 0 | Success | `help`, `system`, `disk` |
| 1 | Operational/runtime failure | host does not resolve, host does not answer ping |
| 2 | Invalid command or input | unknown command, `network` with no host, host with bad characters, extra arguments, disk path that does not exist |

```bash
docker run --rm diagnostic-tool invalid-command; echo $?   # 2
docker run --rm diagnostic-tool network; echo $?           # 2
```

## Docker design

**Dockerfile**

- `alpine:3.20` base, pinned so builds are repeatable. The final image is only a few MB bigger than Alpine itself.
- Only two packages are installed, with `apk add --no-cache`:
  - `bash`, because the scripts use bash features
  - `iputils`, for a `ping` that works as a non-root user
- Everything else (`df`, `ip`, `hostname`, `awk`, ...) already comes with Alpine's busybox.
- Only `app/` is copied into the image, and the scripts get `chmod 755`.
- The container runs as a normal user (`diag`), not root.
- `ENTRYPOINT ["/app/diagnostic.sh"]` with `CMD ["help"]`. Whatever you type after the image name becomes the command, and with nothing typed you get the help.
- The script is also linked as `/usr/local/bin/diagnostic`, so `diagnostic system` works inside the container.

**.dockerignore**

Keeps `.git`, logs, temp files and project files (README, tests, grader, compose file) out of the build context. Only `app/` is needed in the image.

**compose.yaml**

One service, `diagnostic`, that builds the image and tags it `diagnostic-tool`. The container filesystem is `read_only` and `no-new-privileges` is set, since the tool only reads information.

## Testing

```bash
./test.sh                  # builds the image and runs 20 tests
SKIP_BUILD=1 ./test.sh     # reuse an image that is already built
./grade.sh                 # grader supplied with the assignment
```

`test.sh` covers:

- help, `--help` and the default command
- system output (hostname, kernel, memory), and extra arguments rejected
- disk with and without a path, and a missing path rejected
- network on localhost, a missing host, bad characters and extra arguments
- an invalid command and an empty command
- the container not running as root, and the health check passing
- the Compose file being valid, and `docker compose run` working

## Git workflow

- `main` holds the working version.
- `feature/disk-network` added the disk and network commands.
- `feature/docker` added the Dockerfile, .dockerignore, compose.yaml and tests.
- Both branches were merged with `--no-ff` so the merges show in the history.

## Assumptions

- `network` uses ping. Some networks block ICMP. In that case the command still prints the DNS result and interfaces, and exits 1.
- Resolution uses `getent`. If that is missing it falls back to `nslookup`, then `/etc/hosts`.
- `disk` inside the container shows the container's overlay filesystem, which is the Docker host's disk.
- No logs are written inside the container; output goes to stdout and errors to stderr.
