# cache-protocol

Lispy **CLOS** cache API for [cl-stack](https://github.com/egao1980/cl-stack) — get / put (`:ttl` seconds) / delete / incr / CAS. Colocated in-memory TTL backend for tests and the personal profile.

| System | Role | Repo |
|--------|------|------|
| `cache-protocol` (`stack-cache`) | Protocol + `in-memory-ttl-cache` | this repo |
| `cache-backend-redis` | RESP3 / Valkey | [`egao1980/cache-backend-redis`](https://github.com/egao1980/cache-backend-redis) |

```lisp
(asdf:load-system "cache-protocol")

(let ((c (stack-cache:make-in-memory-ttl-cache)))
  (stack-cache:cache-put c "k" "v" :ttl 60)
  (stack-cache:cache-get c "k")
  (stack-cache:cache-incr c "n")
  (stack-cache:cache-cas c "k" "v" "v2"))
```

Expired entries are not returned. `cache-cas` mismatch → `cache-cas-mismatch` with restart `use-value`.

## License

MIT — see [LICENSE](LICENSE).
