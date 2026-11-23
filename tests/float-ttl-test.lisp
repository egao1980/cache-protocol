(in-package #:cache-protocol/tests)

;;; Evidence against PR #3 (fix for #1): ":ttl takes any real" and the
;;; README's ":ttl 0.25 works" hold only while the clock reads small
;;; numbers. %EXPIRES-AT adds the TTL to the clock with CL:+, so a
;;; single-float TTL (what the reader makes of 0.25 or 60.0) turns the
;;; expiry into a single-float: 24 bits of mantissa. Once the clock is
;;; past 2^24 s (194 days of image uptime for MONOTONIC-SECONDS, always for
;;; a Unix-time clock passed as :clock) the expiry is rounded to whole
;;; seconds or minutes, and an entry can be gone the moment it is put.

(defun %cache-at (now)
  "An in-memory cache whose clock reads NOW (seconds, a rational)."
  (cache-protocol:make-in-memory-ttl-cache :clock (lambda () now)))

(deftest float-ttl-on-a-unix-time-clock
  ;; A clock reading Unix seconds with sub-second resolution, the shape of
  ;; Python's time.time(); README: ":clock (a function returning seconds)".
  (let ((c (%cache-at (+ 1795470000 1/10))))
    (cache-protocol:cache-put c "half" "v" :ttl 0.5)
    (ok (equal "v" (cache-protocol:cache-get c "half"))
        ":ttl 0.5 is alive right after the put")
    (cache-protocol:cache-put c "minute" "v" :ttl 60.0)
    (ok (equal "v" (cache-protocol:cache-get c "minute"))
        ":ttl 60.0 (redis-py ex=60.0) is alive right after the put")))

(deftest float-ttl-after-200-days-of-uptime
  ;; MONOTONIC-SECONDS counts from image start; 200 days in, it reads
  ;; 17 280 000 s, where single-floats are 2 s apart.
  (let ((c (%cache-at (+ (* 200 86400) 1/3))))
    (cache-protocol:cache-put c "k" "v" :ttl 0.25)
    (ok (equal "v" (cache-protocol:cache-get c "k"))
        ":ttl 0.25 is alive right after the put on a long-running image")))
