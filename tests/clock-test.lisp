(in-package #:cache-protocol/tests)

;;; Round 3 (#1): the default clock and the tick. On Linux SBCL's
;;; GET-INTERNAL-REAL-TIME reads CLOCK_MONOTONIC_COARSE, so the default
;;; clock moved in 1-4 ms steps and an entry put late in a tick was gone up
;;; to a tick early. MONOTONIC-SECONDS now reads CLOCK_MONOTONIC (Linux) or
;;; CLOCK_MONOTONIC_RAW (macOS) to the nanosecond, and a positive TTL
;;; counts from the end of the put's tick.

(deftest default-clock-steps-finely-on-every-lane
  ;; Uses the clock itself as the reference, so it also runs on Windows,
  ;; where the default is GET-INTERNAL-REAL-TIME.
  (let ((smallest nil)
        (start (cache-protocol:monotonic-seconds))
        (prev (cache-protocol:monotonic-seconds)))
    (loop repeat 5000000
          for now = (cache-protocol:monotonic-seconds)
          do (when (/= now prev)
               (setf smallest (if smallest (min smallest (- now prev)) (- now prev))
                     prev now))
          until (> (- now start) 3/100))
    (ok (and smallest (<= smallest 1/10000))
        (format nil "monotonic-seconds steps by ~A s (~,1F us)"
                smallest (and smallest (* 1d6 smallest))))
    (ok (and smallest (>= smallest cache-protocol:+monotonic-tick+))
        "no step is finer than +monotonic-tick+")))

(deftest default-clock-counts-ttl-from-the-end-of-the-tick
  (let* ((c (cache-protocol:make-in-memory-ttl-cache))
         (before (cache-protocol:monotonic-seconds)))
    (cache-protocol:cache-put c "k" "v" :ttl 1/200)
    (let ((exp (cdr (gethash "k" (cache-protocol::in-memory-ttl-cache-table c)))))
      (ok (>= exp (+ before 1/200 cache-protocol:+monotonic-tick+))
          "expiry is at least the put's reading + TTL + one tick"))
    (cache-protocol:cache-put c "z" "v" :ttl 0)
    (ok (null (cache-protocol:cache-get c "z")) ":ttl 0 is gone at once")
    (cache-protocol:cache-put c "n" "v" :ttl -1)
    (ok (null (cache-protocol:cache-get c "n")) "a negative TTL is gone at once")))

(deftest a-supplied-clock-is-exact
  ;; No tick for a :clock the caller passes: the boundary stays at TTL.
  (multiple-value-bind (c set-now) (%clocked-cache)
    (cache-protocol:cache-put c "k" "v" :ttl 1/200)
    (funcall set-now (+ 1000 1/200))
    (ok (null (cache-protocol:cache-get c "k")) "gone exactly at the TTL")))

(defun %lock-free-p (cache)
  "True when another thread can run a CACHE-GET on CACHE within 2 s, so
this thread does not hold the cache lock."
  (let ((done nil))
    (bt2:make-thread (lambda () (cache-protocol:cache-get cache "probe") (setf done t)))
    (loop repeat 200 until done do (sleep 1/100))
    done))

#+sbcl
(deftest float-infinity-and-nan-ttl
  (multiple-value-bind (c set-now) (%clocked-cache)
    (cache-protocol:cache-put c "inf" "v" :ttl sb-ext:double-float-positive-infinity)
    (cache-protocol:cache-put c "inf1" "v" :ttl sb-ext:single-float-positive-infinity)
    (funcall set-now (expt 10 12))
    (ok (equal "v" (cache-protocol:cache-get c "inf")) "+inf never expires")
    (ok (equal "v" (cache-protocol:cache-get c "inf1")) "single-float +inf never expires")
    (cache-protocol:cache-put c "neg" "v" :ttl sb-ext:double-float-negative-infinity)
    (ok (null (cache-protocol:cache-get c "neg")) "-inf is gone at once")
    (let ((nan (sb-int:with-float-traps-masked (:invalid)
                 (- sb-ext:double-float-positive-infinity
                    sb-ext:double-float-positive-infinity)))
          (lock-free nil))
      (ok (handler-case
              (handler-bind ((cache-protocol:cache-error
                              (lambda (e)
                                (declare (ignore e))
                                (setf lock-free (%lock-free-p c)))))
                (cache-protocol:cache-put c "nan" "v" :ttl nan)
                nil)
            (cache-protocol:cache-error () t))
          "a NaN TTL signals cache-error")
      (ok lock-free "the NaN error is signalled with no lock held")
      (ok (handler-case (progn (cache-protocol:cache-cas c "inf" "v" "w" :ttl nan) nil)
            (cache-protocol:cache-error () t))
          "cache-cas refuses a NaN TTL too")
      (ok (equal "v" (cache-protocol:cache-get c "inf")) "the refused CAS stored nothing"))))
