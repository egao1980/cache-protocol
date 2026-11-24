(in-package #:cache-protocol/tests)

;;; Round-2 evidence against PR #3 (fix for #1), a platform difference.
;;; README: "The default clock (monotonic-seconds) has
;;; internal-time-units-per-second resolution". MONOTONIC-SECONDS is
;;; GET-INTERNAL-REAL-TIME, and SBCL reads CLOCK_MONOTONIC_COARSE for it on
;;; Linux (src/code/unix.lisp: "#+linux clock-monotonic-coarse"): one
;;; kernel tick, 1 ms at HZ=1000 and 4 ms at HZ=250, not 1 us. Both the put
;;; and the get read that truncated clock, so an entry put late in a tick
;;; is gone up to a tick BEFORE its TTL has elapsed. macOS reads
;;; CLOCK_MONOTONIC and passes; the ubuntu lane does not. Python's
;;; TTLCache and Redis (PX) keep a 5 ms TTL alive for 5 ms.

#+(and sbcl unix)
(defun %fine-us ()
  "Reference time in microseconds (gettimeofday), finer than a kernel tick."
  (multiple-value-bind (s us) (sb-ext:get-time-of-day)
    (+ (* s 1000000) us)))

(deftest default-clock-has-the-documented-resolution
  #-(and sbcl unix) (skip "needs SBCL on Unix for the reference clock")
  #+(and sbcl unix)
  (let ((smallest nil)
        (end (+ (%fine-us) 30000))
        (prev (cache-protocol:monotonic-seconds)))
    (loop while (< (%fine-us) end)
          do (let ((now (cache-protocol:monotonic-seconds)))
               (when (/= now prev)
                 (setf smallest (if smallest (min smallest (- now prev)) (- now prev))
                       prev now))))
    (ok (and smallest (<= smallest 1/10000))
        (format nil "monotonic-seconds steps by ~A s (~,1F us)"
                smallest (and smallest (* 1d6 smallest))))))

(deftest ttl-is-never-cut-short-default-clock
  #-(and sbcl unix) (skip "needs SBCL on Unix for the reference clock")
  #+(and sbcl unix)
  (let ((c (cache-protocol:make-in-memory-ttl-cache))
        (early 0)
        (worst 0))
    (dotimes (i 200)
      ;; T0 is read before the put, so the TTL cannot have elapsed while
      ;; less than 5 ms have passed since T0 (0.1 ms margin).
      (let ((t0 (%fine-us)))
        (cache-protocol:cache-put c "k" "v" :ttl 1/200)
        (loop for elapsed = (- (%fine-us) t0)
              while (< elapsed 4900)
              unless (cache-protocol:cache-get c "k")
                do (incf early)
                   (setf worst (max worst (- 5000 elapsed)))
                   (return))))
    (ok (zerop early)
        (format nil ":ttl 1/200 (5 ms) was gone early in ~D of 200 puts, up to ~D us early"
                early worst))))
