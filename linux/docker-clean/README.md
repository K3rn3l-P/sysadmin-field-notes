# Deep Docker cleanup – Linux

## Purpose
Quick guide to reclaiming space on a Linux host by clearing the Docker build cache, images,
containers, volumes and other unused resources.

## Prerequisites

- Docker installed and running
- Adequate permissions (`sudo`) on the host
- Awareness that some of these commands remove data not referenced by any running container

## 1. Clear unused build cache and dangling images

```bash
docker builder prune -f
docker image prune -f
```

This frees space by removing build layers that are no longer used, plus orphaned images.

## 2. Extended cleanup

```bash
docker system prune -a -f
```

> **Note:**
> `system prune -a` may force you to pull images again next time (slower), but it frees a lot of
> space.

## 3. Container logs

```bash
docker logs watchtower-tmc -f
```

Use this to follow a specific container's logs in real time.

## 4. Removing specific containers and resources

```bash
docker stop postgres pgadmin4
docker rm postgres pgadmin4
docker volume rm postgres pgadmin4
docker network rm pgnetwork
```

These stop and delete specific containers, volumes and networks.

## 5. Removing everything with Docker Compose

```bash
docker compose down -v
```

This stops the services defined in `docker-compose.yml` and removes the associated volumes.

## 6. Getting into a specific container

Here, for the container with ID `e4ebd319af69`:

### 6.1 Use `docker exec` for an interactive shell

```bash
docker exec -it e4ebd319af69 /bin/sh
```

If the container has `bash`, use that instead:

```bash
docker exec -it e4ebd319af69 /bin/bash
```

### 6.2 Use `docker attach` to hook onto the container's output

```bash
docker attach e4ebd319af69
```

> Note: with `docker attach` you can lose control of the terminal if the container isn't set up to
> accept interactive input.

### 6.3 Check which shells exist in the container

```bash
docker exec -it e4ebd319af69 which bash
docker exec -it e4ebd319af69 which sh
```

If one of them isn't there, use whichever is.

---

## Important notes

- Always check with `docker system df` before and after a cleanup.
- Avoid `docker system prune -a -f` on production hosts without a rollback plan.
- Check whether there are containers or mounted volumes you don't want to delete.

---

**Last updated:** April 2026
