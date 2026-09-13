(in-package #:cache-protocol/tests)

(deftest cas-use-value
  (let ((c (cache-protocol:make-in-memory-ttl-cache))
        (got nil))
    (cache-protocol:cache-put c "k" "old")
    (handler-bind ((cache-protocol:cache-cas-mismatch
                    (lambda (cond)
                      (use-value :forced cond))))
      (setf got (cache-protocol:cache-cas c "k" "nope" "new")))
    (ok (eq :forced got))))
