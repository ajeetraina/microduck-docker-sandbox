# 🦆 microduck-docker-sandbox

**Run the [Microduck](https://pollen-robotics.com/microduck) robot simulator inside a
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) microVM - isolated, with the
network switched off.**

This repo wraps the [`ajeetraina777/microduck-docker`](https://hub.docker.com/r/ajeetraina777/microduck-docker)
image and runs it inside an `sbx` microVM instead of straight on your Docker host.

> **Prerequisite:** the wrapper runs `ajeetraina777/microduck-docker:latest`. Publish that
> image to your Docker Hub first (or override `IMAGE=<your-image>` when running the scripts).

## Why bother?

The simulator ships a small **lab API** that can create *and delete* training runs. You
probably don't want that reachable from your network - the upstream `docker-compose.yml`
even binds it to loopback only for this reason.

A Docker Sandbox goes further: the simulator runs behind a **hypervisor boundary**, on its
own kernel, with its own Docker daemon, and - because the image needs **no network at
runtime** - you can run it under the **Locked Down** network policy. Nothing the lab API
does can reach your host or the internet. You still watch the duck walk in your browser.

## Quick start

```bash
# 0. one-time: install + log in (pick the "Locked Down" policy when asked)
brew install docker/tap/sbx
sbx login

# 1. bring the image in air-gapped, then launch everything
./scripts/export-image.sh          # host: pulls the image, saves it to ./microduck.tar
./scripts/sbx-run.sh               # boots the microVM, loads + runs the sim, forwards ports

# 2. watch the duck
open http://localhost:63317
```

Prefer to just let it pull inside the sandbox instead of air-gapping? See
[`docs/sandbox-setup.md`](docs/sandbox-setup.md) for the networked variant and the manual,
step-by-step walkthrough behind these scripts.

### Declarative (`sbxenv.yaml`)

The same environment is also described declaratively in [`sbxenv.yaml`](sbxenv.yaml), so you
can skip the scripts and let `sbx` manage the whole lifecycle:

```bash
sbx env plan ./sbxenv.yaml     # preview what it will do (changes nothing)
sbx env run  ./sbxenv.yaml     # create the sandbox, load + run the sim, forward ports
sbx env rm   ./sbxenv.yaml     # tear it all down
```

It mounts this repo, publishes both ports, and uses lifecycle hooks to build `microduck.tar`
(if missing) and start the simulator inside the sandbox. `sbx env` is **experimental**, so
the scripts above remain the supported path. Override the image with
`sbx env run ./sbxenv.yaml --env-arg image=<your-image>`.

## Ports

| Port    | What it is                              |
|---------|-----------------------------------------|
| `63317` | the 3D viewer - **open this**           |
| `8788`  | physics + brains (required, not for you) |

## How it actually works

`sbx` sandboxes are microVMs meant to host a coding agent, not arbitrary images - so the
simulator runs as a **nested container inside the sandbox's own Docker daemon**, and the
viewer is reached through two hops:

```
your browser ──localhost:63317──▶ sbx (host→VM forward) ──▶ microduck container (:63317)
```

Full details, security notes, and the gotchas (`0.0.0.0` bind, port maps dropping on
`sbx stop`) live in [`docs/sandbox-setup.md`](docs/sandbox-setup.md).

## License

Apache 2.0 - see [LICENSE](LICENSE). The Microduck simulator image is a separate upstream
project with its own license.
