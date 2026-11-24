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
  "The clock reading as a rational. A float reading is taken exactly
(CL:RATIONAL), so no float reaches the expiry arithmetic."
  (let ((now (funcall (cache-clock cache))))
    (if (floatp now) (rational now) now)))

(defmacro with-cache-lock ((cache) &body body)
  `(bt2:with-recursive-lock-held ((in-memory-ttl-cache-lock ,cache))
     ,@body))

(defun %expires-at (cache ttl)
  "Absolute expiry TTL seconds from now, as a rational, or NIL. A float
TTL is RATIONALIZEd (0.1 -> 1/10) first: added to the clock as a float, a
single-float :ttl would make the expiry a single-float, 24 bits of
mantissa, and past 2^24 s (194 days of uptime, or any Unix-time clock) the
expiry would be rounded to whole seconds or minutes."
  (and ttl
       (+ (%now cache)
          (if (floatp ttl) (rationalize ttl) ttl))))

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
  "Redis string2ll syntax: an optional minus sign, then a non-zero digit
and more ASCII digits, or a lone \"0\". \"007\", \"-0\", \"+1\" and \" 1\"
are refused, as INCR refuses them."
  (let* ((len (length string))
         (start (if (and (plusp len) (char= #\- (char string 0))) 1 0)))
    (flet ((digitp (c) (char<= #\0 c #\9)))
      (cond
       ((= start len) nil)
       ((string= string "0") t)
       (t (and (char<= #\1 (char string start) #\9)
               (every #'digitp (subseq string start))))))))

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
  ;; INCR keeps the TTL). Values and results stay in (signed-byte 64), as
  ;; on Redis. Errors are reported after the lock is released, so handlers
  ;; never run while holding it.
  (multiple-value-bind (new problem)
      (with-cache-lock (cache)
        (let* ((entry (%live-entry cache key))
               (cur (car entry))
               (base (cond
                      ((null cur) 0)
                      ((integerp cur) cur)
                      ((and (stringp cur) (%integer-text-p cur))
                       (parse-integer cur)))))
          (cond
           ((or (null base)
                (not (typep base '(signed-byte 64)))
                (not (typep delta '(signed-byte 64))))
            (values nil (format nil "value is not an integer or out of range: ~s"
                                cur)))
           ((not (typep (+ base delta) '(signed-byte 64)))
            (values nil (format nil "increment or decrement would overflow: ~s + ~s"
                                base delta)))
           (t (%store cache key (+ base delta) (cdr entry))))))
    (when problem
      (error 'cache-error :key key :message problem))
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
