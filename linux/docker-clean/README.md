# Pulizia avanzata Docker – Linux

## Scopo
Guida rapida per liberare spazio su host Linux tramite la pulizia della cache Docker, immagini, container, volumi e risorse non usate.

## Prerequisiti

- Docker installato e funzionante
- Accesso con permessi adeguati (`sudo`) sul host
- Consapevolezza che alcuni comandi rimuovono dati non riferiti da container attivi

## 1. Cancella cache build inutilizzata / immagini non usate

```bash
docker builder prune -f
docker image prune -f
```

Questa operazione libera spazio rimuovendo layer di build non più usati e immagini orfane.

## 2. Pulizia estesa

```bash
docker system prune -a -f
```

> **Nota:**
> `system prune -a` può farti riscaricare immagini la prossima volta (più lento), ma libera parecchio spazio.

## 3. Log container

```bash
docker logs watchtower-tmc -f
```

Usa questo comando per seguire in tempo reale i log di uno specifico container.

## 4. Rimozione di container e risorse specifici

```bash
docker stop postgres pgadmin4
docker rm postgres pgadmin4
docker volume rm postgres pgadmin4
docker network rm pgnetwork
```

Questi comandi fermano e cancellano container, volumi e network specifici.

## 5. Rimozione globale con Docker Compose

```bash
docker compose down -v
```

Questo comando ferma i servizi definiti da `docker-compose.yml` e rimuove i volumi associati.

## 6. Accesso a un container specifico

Nel caso specifico del container con l'ID `e4ebd319af69`:

### 6.1 Usa `docker exec` per accedere alla shell interattiva

```bash
docker exec -it e4ebd319af69 /bin/sh
```

Se il container usa `bash`, sostituisci con:

```bash
docker exec -it e4ebd319af69 /bin/bash
```

### 6.2 Usa `docker attach` per collegarti all'output del container

```bash
docker attach e4ebd319af69
```

> Nota: Se utilizzi `docker attach`, potresti perdere il controllo del terminale se il container non è configurato per supportare input interattivo.

### 6.3 Verifica la presenza di una shell nel container

```bash
docker exec -it e4ebd319af69 which bash
docker exec -it e4ebd319af69 which sh
```

Se una delle shell non esiste, usa quella disponibile.

---

## Note importanti

- Fai sempre un controllo con `docker system df` prima e dopo le pulizie.
- Evita `docker system prune -a -f` su host di produzione senza avere un piano di rollback.
- Controlla se ci sono container importanti o volumi montati che non vuoi cancellare.

---

**Ultimo aggiornamento:** Aprile 2026
