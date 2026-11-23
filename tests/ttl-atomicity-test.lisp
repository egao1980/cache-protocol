(in-package #:cache-protocol/tests)

;;; Evidence for egao1980/cache-protocol#1.
;;;
;;; 1. TTL precision: with the default clock an entry put with :ttl 1
;;;    must be gone once one second has elapsed (Redis: ms precision).
;;; 2. Atomicity: cache-incr and cache-cas are read-modify-write; on a
;;;    backend shared between threads they must not lose updates and
;;;    exactly one of several racing CAS calls on the same expected
;;;    value may win (the Redis backend gives both).

(defun %wait-for-second-boundary ()
  "Return just after GET-UNIVERSAL-TIME ticks, so the next put lands at
the start of a wall-clock second."
  (let ((start (get-universal-time)))
    (loop while (= start (get-universal-time))
          do (sleep 0.005))))

(deftest ttl-expires-once-elapsed-default-clock
  (testing "put :ttl 1, read back 1.1 s later with the default clock"
    (let ((c (cache-protocol:make-in-memory-ttl-cache)))
      (%wait-for-second-boundary)
      (cache-protocol:cache-put c "k" "v" :ttl 1)
      (sleep 1.1)
      (ok (null (cache-protocol:cache-get c "k"))
          "entry is expired 1.1 s after a :ttl 1 put"))))

(defun %run-threads (n fn)
  "Start N threads running (FN i) after a common start flag, join them,
and return the list of their results. An error in a thread is returned
as the condition object."
  (let* ((go (list nil))
         (threads
           (loop for i below n
                 collect (let ((i i))
                           (bt2:make-thread
                            (lambda ()
                              (loop until (car go))
                              (handler-case (funcall fn i)
                                (error (e) e)))
                            :name (format nil "cache-race-~D" i))))))
    (setf (car go) t)
    (mapcar #'bt2:join-thread threads)))

(deftest incr-is-atomic-across-threads
  (let* ((c (cache-protocol:make-in-memory-ttl-cache))
         (threads 8)
         (per-thread 20000)
         (results (%run-threads threads
                                (lambda (i)
                                  (declare (ignore i))
                                  (dotimes (k per-thread)
                                    (cache-protocol:cache-incr c "n"))
                                  :done)))
         (errors (remove :done results)))
    (ok (null errors)
        (format nil "no thread signalled an error (first: ~@[~A~])"
                (first errors)))
    (ok (eql (* threads per-thread) (cache-protocol:cache-get c "n"))
        (format nil "~D concurrent incrs, none lost (got ~S)"
                (* threads per-thread)
                (cache-protocol:cache-get c "n")))))

(deftest cas-counter-has-no-double-winners
  ;; Each thread reads N and CASes N -> N+1. Every successful CAS moves
  ;; the value by exactly one, so the final value equals the number of
  ;; wins. Two threads that both pass the compare for the same N win
  ;; twice while the value moves once.
  (let* ((c (cache-protocol:make-in-memory-ttl-cache))
         (threads 8)
         (attempts 20000))
    (cache-protocol:cache-put c "k" 0)
    (let* ((results
            (%run-threads
             threads
             (lambda (i)
               (declare (ignore i))
               (let ((wins 0))
                 (dotimes (a attempts wins)
                   (let ((seen (cache-protocol:cache-get c "k")))
                     (handler-case
                         (progn (cache-protocol:cache-cas c "k" seen (1+ seen))
                           (incf wins))
                       (cache-protocol:cache-cas-mismatch () nil))))))))
           (errors (remove-if #'integerp results))
           (wins (reduce #'+ (remove-if-not #'integerp results))))
      (ok (null errors)
          (format nil "no thread signalled an error (first: ~@[~A~])"
                  (first errors)))
      (ok (eql wins (cache-protocol:cache-get c "k"))
          (format nil "value equals successful CAS count (~D wins, value ~S)"
                  wins (cache-protocol:cache-get c "k"))))))
