(in-package #:cache-protocol/tests)

;;; Edge cases around the #1 / #2 fixes: expiry boundary, fractional TTL,
;;; INCR keeping the TTL and refusing non-integer text, CAS on a missing
;;; key, DELETE of an expired entry.

(defun %clocked-cache ()
  "A cache on a settable clock. → (values cache setter)."
  (let* ((now 1000)
         (c (cache-protocol:make-in-memory-ttl-cache :clock (lambda () now))))
    (values c (lambda (v) (setf now v)))))

(deftest ttl-expires-exactly-at-expiry
  (multiple-value-bind (c set-now) (%clocked-cache)
    (cache-protocol:cache-put c "k" "v" :ttl 10)
    (funcall set-now 1009)
    (ok (equal "v" (cache-protocol:cache-get c "k")) "alive before TTL elapses")
    (funcall set-now 1010)
    (ok (null (cache-protocol:cache-get c "k")) "gone once TTL has elapsed")))

(deftest ttl-accepts-fractional-seconds
  (multiple-value-bind (c set-now) (%clocked-cache)
    (cache-protocol:cache-put c "k" "v" :ttl 1/2)
    (funcall set-now (+ 1000 1/4))
    (ok (equal "v" (cache-protocol:cache-get c "k")) "alive at 0.25 s")
    (funcall set-now (+ 1000 1/2))
    (ok (null (cache-protocol:cache-get c "k")) "gone at 0.5 s"))
  (let ((c (cache-protocol:make-in-memory-ttl-cache)))
    (cache-protocol:cache-put c "k" "v" :ttl 0.2)
    (ok (equal "v" (cache-protocol:cache-get c "k")) "default clock: alive at once")
    (sleep 0.3)
    (ok (null (cache-protocol:cache-get c "k")) "default clock: gone after 0.3 s")))

(deftest default-clock-is-sub-second
  (let ((c (cache-protocol:make-in-memory-ttl-cache)))
    (ok (not (integerp (loop for v = (funcall (cache-protocol:cache-clock c))
                             repeat 100
                             unless (integerp v) return v
                             finally (return v))))
        "the default clock has sub-second resolution")))

(deftest incr-keeps-ttl
  (multiple-value-bind (c set-now) (%clocked-cache)
    (cache-protocol:cache-put c "n" 1 :ttl 10)
    (ok (= 2 (cache-protocol:cache-incr c "n")))
    (funcall set-now 1005)
    (ok (= 3 (cache-protocol:cache-incr c "n")) "still counting inside the window")
    (funcall set-now 1011)
    (ok (null (cache-protocol:cache-get c "n")) "the counter expires with its TTL")
    (ok (= 1 (cache-protocol:cache-incr c "n")) "a new window starts at 0")
    (funcall set-now 2000)
    (ok (= 1 (cache-protocol:cache-get c "n")) "the new counter has no TTL")))

(deftest incr-parses-integer-text
  (let ((c (cache-protocol:make-in-memory-ttl-cache)))
    (cache-protocol:cache-put c "a" "41")
    (ok (= 42 (cache-protocol:cache-incr c "a")))
    (cache-protocol:cache-put c "b" "-3")
    (ok (= -1 (cache-protocol:cache-incr c "b" :delta 2)))))

(deftest-parametrize incr-rejects-non-integer-text
    ((value)
     ("-") ("") ("1-2") (" 1") ("+1") ("abc") (1.5) (:keyword))
  (let ((c (cache-protocol:make-in-memory-ttl-cache)))
    (cache-protocol:cache-put c "k" value)
    (ok (signals (cache-protocol:cache-incr c "k") 'cache-protocol:cache-error)
        (format nil "incr on ~S signals cache-error" value))
    (ok (equal value (cache-protocol:cache-get c "k")) "the value is unchanged")))

(deftest cas-nil-expected-matches-missing-key
  (let ((c (cache-protocol:make-in-memory-ttl-cache)))
    (ok (equal "first" (cache-protocol:cache-cas c "k" nil "first")))
    (ok (signals (cache-protocol:cache-cas c "k" nil "second")
                 'cache-protocol:cache-cas-mismatch)
        "a second create-if-absent loses")))

(deftest cas-sets-ttl
  (multiple-value-bind (c set-now) (%clocked-cache)
    (cache-protocol:cache-put c "k" "old")
    (cache-protocol:cache-cas c "k" "old" "new" :ttl 5)
    (funcall set-now 1005)
    (ok (null (cache-protocol:cache-get c "k")) "CAS :ttl applies to the new value")))

(deftest cas-on-expired-entry-sees-nil
  (multiple-value-bind (c set-now) (%clocked-cache)
    (cache-protocol:cache-put c "k" "old" :ttl 1)
    (funcall set-now 1001)
    (ok (signals (cache-protocol:cache-cas c "k" "old" "new")
                 'cache-protocol:cache-cas-mismatch)
        "an expired value no longer matches")
    (ok (equal "new" (cache-protocol:cache-cas c "k" nil "new"))
        "it matches NIL instead")))

(deftest delete-of-expired-entry-reports-absent
  (multiple-value-bind (c set-now) (%clocked-cache)
    (cache-protocol:cache-put c "k" "v" :ttl 1)
    (funcall set-now 1001)
    (ok (null (cache-protocol:cache-delete c "k")) "like Redis DEL: 0 for an expired key")))

(deftest cache-connection-error-is-a-cache-error
  (let ((c (make-condition 'cache-protocol:cache-connection-error
                           :message "refused" :cause "ECONNREFUSED")))
    (ok (typep c 'cache-protocol:cache-error))
    (ok (equal "ECONNREFUSED" (cache-protocol:cache-connection-error-cause c)))
    (ok (search "refused" (princ-to-string c)))))
