(in-package #:cache-protocol/tests)

(deftest put-get-delete
  (let ((c (cache-protocol:make-in-memory-ttl-cache)))
    (ok (string= "v" (cache-protocol:cache-put c "k" "v")))
    (ok (string= "v" (cache-protocol:cache-get c "k")))
    (ok (cache-protocol:cache-delete c "k"))
    (ok (null (cache-protocol:cache-get c "k")))))

(deftest ttl-expires
  (let* ((now 1000)
         (c (cache-protocol:make-in-memory-ttl-cache
             :clock (lambda () now))))
    (cache-protocol:cache-put c "k" "v" :ttl 10)
    (ok (string= "v" (cache-protocol:cache-get c "k")))
    (incf now 11)
    (ok (null (cache-protocol:cache-get c "k")))))

(deftest incr
  (let ((c (cache-protocol:make-in-memory-ttl-cache)))
    (ok (= 1 (cache-protocol:cache-incr c "n")))
    (ok (= 3 (cache-protocol:cache-incr c "n" :delta 2)))))

(deftest cas-success
  (let ((c (cache-protocol:make-in-memory-ttl-cache)))
    (cache-protocol:cache-put c "k" "old")
    (ok (string= "new" (cache-protocol:cache-cas c "k" "old" "new")))
    (ok (string= "new" (cache-protocol:cache-get c "k")))))

(deftest cas-mismatch-signals
  (let ((c (cache-protocol:make-in-memory-ttl-cache)))
    (cache-protocol:cache-put c "k" "old")
    (ok (signals (cache-protocol:cache-cas c "k" "other" "new")
                 'cache-protocol:cache-cas-mismatch))))
