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

`in-memory-ttl-cache` behaves like Redis where the protocol says so:

- **TTL** is seconds as a real (`:ttl 1/2` and `:ttl 0.25` work). An entry is gone once its TTL has elapsed. Expiry arithmetic is exact: a float TTL is `rationalize`d and a float clock reading is taken as a rational, so a single-float `:ttl 0.5` stays 0.5 s on a Unix-time clock or after months of uptime. The default clock (`monotonic-seconds`) has `internal-time-units-per-second` resolution and does not follow wall-clock steps; pass `:clock` (a function returning seconds) to drive time in tests.
- **Atomic.** Every operation runs under one recursive bt2 lock, so `cache-incr` loses no updates and of several threads racing `cache-cas` on the same expected value exactly one wins. Share one cache between threads freely.
- `cache-incr` keeps the entry's TTL (Redis `INCR`), counts a missing key from 0, and accepts integers or integer text in Redis `string2ll` form (`"-12"`, `"0"`; not `"007"`, `"-0"`, `"+1"`). Values and results stay in `(signed-byte 64)`, as on Redis. Anything else, or an overflow, signals `cache-error`.
- `cache-cas` with expected `nil` matches a missing (or expired) key: create-if-absent. A mismatch signals `cache-cas-mismatch` with restart `use-value`.

Conditions: `cache-error` (slots `key`, `message`) → `cache-cas-mismatch` (`expected`, `actual`), `cache-connection-error` (`cause`; signalled by network backends).

## License

MIT — see [LICENSE](LICENSE).
