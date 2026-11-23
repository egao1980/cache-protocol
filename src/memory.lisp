(in-package #:cache-protocol)

(defun monotonic-seconds ()
  "Seconds since an arbitrary fixed point, as a rational with the
resolution of INTERNAL-TIME-UNITS-PER-SECOND. The default cache clock."
  (/ (get-internal-real-time) internal-time-units-per-second))

(defclass in-memory-ttl-cache (cache-backend)
  ((table :initform (make-hash-table :test #'equal)
          :accessor in-memory-ttl-cache-table)
   (lock :initform (bt2:make-recursive-lock :name "in-memory-ttl-cache")
         :reader in-memory-ttl-cache-lock)
   (clock :initarg :clock :accessor cache-clock
          :initform #'monotonic-seconds))
  (:documentation
   "Process-local cache with per-entry TTL. Every operation runs under one
lock, so CACHE-INCR and CACHE-CAS are atomic across threads, as on Redis.
CLOCK is a function of no arguments returning seconds as a real; the
default, MONOTONIC-SECONDS, has the resolution of
INTERNAL-TIME-UNITS-PER-SECOND and does not follow wall-clock steps."))

(defun make-in-memory-ttl-cache (&key clock)
  (if clock
      (make-instance 'in-memory-ttl-cache :clock clock)
      (make-instance 'in-memory-ttl-cache)))

(defun use-in-memory-ttl-cache (&key clock)
  (setf *cache-backend* (make-in-memory-ttl-cache :clock clock)))

(defun %now (cache)
  (funcall (cache-clock cache)))

(defmacro with-cache-lock ((cache) &body body)
  `(bt2:with-recursive-lock-held ((in-memory-ttl-cache-lock ,cache))
     ,@body))

(defun %expires-at (cache ttl)
  (and ttl (+ (%now cache) ttl)))

(defun %expired-p (cache entry)
  "An entry is gone once its TTL has fully elapsed: expiry <= now."
  (let ((exp (cdr entry)))
    (and exp (<= exp (%now cache)))))

(defun %live-entry (cache key)
  "The live (value . expiry) cell for KEY, or NIL. Drops an expired cell.
The caller holds the cache lock."
  (let* ((table (in-memory-ttl-cache-table cache))
         (entry (gethash key table)))
    (cond
     ((null entry) nil)
     ((%expired-p cache entry)
      (remhash key table)
      nil)
     (t entry))))

(defun %store (cache key value expiry)
  "Store VALUE at KEY with absolute EXPIRY (or NIL). The caller holds the lock."
  (setf (gethash key (in-memory-ttl-cache-table cache))
        (cons value expiry))
  value)

(defun %integer-text-p (string)
  "Redis INCR syntax: an optional minus sign, then one or more ASCII digits."
  (let ((start (if (and (plusp (length string))
                        (char= #\- (char string 0)))
                   1
                   0)))
    (and (< start (length string))
         (every (lambda (c) (char<= #\0 c #\9))
                (subseq string start)))))

(defmethod cache-get ((cache in-memory-ttl-cache) key &key)
  (with-cache-lock (cache)
    (car (%live-entry cache key))))

(defmethod cache-put ((cache in-memory-ttl-cache) key value &key ttl)
  (check-type ttl (or null real))
  (with-cache-lock (cache)
    (%store cache key value (%expires-at cache ttl))))

(defmethod cache-delete ((cache in-memory-ttl-cache) key &key)
  (with-cache-lock (cache)
    (let ((live (%live-entry cache key)))
      (remhash key (in-memory-ttl-cache-table cache))
      (and live t))))

(defmethod cache-incr ((cache in-memory-ttl-cache) key &key (delta 1))
  (check-type delta integer)
  ;; Read, add and store under the lock; keep the entry's expiry (Redis
  ;; INCR keeps the TTL). A non-integer value is reported after the lock
  ;; is released, so handlers never run while holding it.
  (multiple-value-bind (new bad-entry)
      (with-cache-lock (cache)
        (let* ((entry (%live-entry cache key))
               (cur (car entry)))
          (cond
           ((null cur)
            (%store cache key delta (cdr entry)))
           ((integerp cur)
            (%store cache key (+ cur delta) (cdr entry)))
           ((and (stringp cur) (%integer-text-p cur))
            (%store cache key (+ (parse-integer cur) delta) (cdr entry)))
           (t (values nil entry)))))
    (when bad-entry
      (error 'cache-error :key key
                          :message (format nil "not an integer: ~s"
                                           (car bad-entry))))
    new))

(defmethod cache-cas ((cache in-memory-ttl-cache) key expected new &key ttl)
  (check-type ttl (or null real))
  ;; Compare and store in one critical section: of several threads that
  ;; saw the same EXPECTED, exactly one swaps. The mismatch is signalled
  ;; after the lock is released.
  (multiple-value-bind (swapped actual)
      (with-cache-lock (cache)
        (let ((actual (car (%live-entry cache key))))
          (if (equal actual expected)
              (progn
                (%store cache key new (%expires-at cache ttl))
                (values t actual))
              (values nil actual))))
    (if swapped
        new
        (restart-case
            (error 'cache-cas-mismatch
                   :key key :expected expected :actual actual)
          (use-value (value)
            :report "Use a supplied value (treat CAS as success)"
            value)))))
