# Running Microduck inside a Docker Sandbox

This is the long-form version of what the `scripts/` automate. Read it if a script fails,
if your `sbx` version behaves differently, or if you just want to run the steps by hand.

> Tested shape, not a guarantee: `sbx` is young and its flags move between releases. If a
> command errors, run the steps one at a time and adjust - the model below is stable even
> when the exact flags drift.

## The model

An `sbx` sandbox is a **microVM** with its own Linux kernel and its own **isolated Docker
daemon**. It is designed to host a coding agent, not to *be* an arbitrary image. So we run
the simulator as a **nested container** inside the sandbox and forward its ports out:

```
your browser ──localhost:63317──▶ sbx (host→VM forward) ──▶ microduck container (:63317)
                                                        └──▶ microduck container (:8788)
```

## Prerequisites

```bash
brew install docker/tap/sbx     # macOS; Docker Desktop NOT required
sbx login                       # choose "Locked Down" for the air-gapped story below
docker version                  # host Docker, only needed for the air-gapped export
```

## Option A - air-gapped (recommended)

The image does **no downloads at runtime**, so once it is loaded the sandbox needs zero
network. This is the whole point: the delete-capable lab API ends up behind a hypervisor
boundary *and* a deny-all network policy, yet still works.

```bash
# 1. host: pull once and save to a tar in this repo (the dir we'll mount)
docker pull ajeetraina777/microduck-docker:latest
docker save ajeetraina777/microduck-docker:latest -o ./microduck.tar

# 2. create a docker-enabled sandbox, mounting this repo so the tar is visible inside
sbx create shell "$PWD" --name microduck -m 4GB

# 3. confirm a Docker daemon is present inside
sbx exec microduck docker info >/dev/null && echo "docker ok"

# 4. load the image and run it (detached) inside the sandbox
sbx exec microduck docker load -i "$PWD/microduck.tar"
sbx exec -d microduck docker run --rm \
  -p 63317:63317 -p 8788:8788 ajeetraina777/microduck-docker:latest

# 5. host: forward both ports out of the VM
sbx ports microduck --publish 63317:63317 --publish 8788:8788

# 6. open the viewer
open http://localhost:63317
```

## Option B - networked (simplest)

Let the sandbox pull the image itself. Requires allowing Docker Hub through the policy.

```bash
sbx policy allow network "registry-1.docker.io,auth.docker.io,*.docker.com"
sbx create shell --name microduck -m 4GB
sbx exec microduck docker info >/dev/null && echo "docker ok"
sbx exec -d microduck docker run --rm \
  -p 63317:63317 -p 8788:8788 ajeetraina777/microduck-docker:latest
sbx ports microduck --publish 63317:63317 --publish 8788:8788
open http://localhost:63317
```

## Gotchas

- **Bind address.** `sbx` only forwards services bound to `0.0.0.0`. The inner
  `docker run -p 63317:63317` already publishes on the VM's `0.0.0.0`, so you're fine. Note
  this is the *opposite* of upstream's `127.0.0.1` compose binding - safe here, because the
  microVM is the isolation boundary.
- **Port maps are lost on `sbx stop`.** After any stop/reconnect, re-run the `sbx ports`
  command.
- **`docker info` fails?** The `shell` template on your `sbx` build may not include a
  daemon. Use a `-docker` variant template (`sbx create --template …`) - see
  `sbx run --help` and the custom-environments docs.
- **Memory.** MuJoCo physics + the shipped brains want headroom; `-m 4GB` is a safe floor.
  Bump it if the container is OOM-killed.
- **Disk.** The tar + the loaded image live on the VM's disk. If `docker load` runs out of
  space, give the sandbox a larger docker-size (see `sbx` docs).

## Managing the sandbox

```bash
sbx ls                                  # see status + port mappings
sbx exec -it microduck bash             # shell inside the VM
sbx exec microduck docker logs -f $(sbx exec microduck docker ps -q)   # sim logs
sbx stop microduck                      # pause (then re-run sbx ports on restart)
sbx rm microduck                        # delete
```

## Security notes

- The hypervisor boundary - not in-VM privilege separation - is the control. Agents/root
  inside the VM is by design.
- **Workspace is the residual risk.** We mount this repo read-write only to carry
  `microduck.tar` in; nothing writes back. If you prefer, mount it `:ro` and copy the tar
  in another way. After a session, `git diff` and check `.git/hooks/` out of habit.
- Under **Locked Down** with Option A, the sandbox has no egress at all - the strongest
  posture, and the reason this repo exists.
