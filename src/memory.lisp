(in-package #:cache-protocol)

(defclass in-memory-ttl-cache (cache-backend)
  ((table :initform (make-hash-table :test #'equal)
          :accessor in-memory-ttl-cache-table)
   (clock :initarg :clock :accessor cache-clock
          :initform #'get-universal-time)))

(defun make-in-memory-ttl-cache (&key clock)
  (if clock
      (make-instance 'in-memory-ttl-cache :clock clock)
      (make-instance 'in-memory-ttl-cache)))

(defun use-in-memory-ttl-cache (&key clock)
  (setf *cache-backend* (make-in-memory-ttl-cache :clock clock)))

(defun %now (cache)
  (funcall (cache-clock cache)))

(defun %expired-p (cache entry)
  (let ((exp (cdr entry)))
    (and exp (< exp (%now cache)))))

(defun %lookup (cache key)
  (let ((entry (gethash key (in-memory-ttl-cache-table cache))))
    (cond
      ((null entry) nil)
      ((%expired-p cache entry)
       (remhash key (in-memory-ttl-cache-table cache))
       nil)
      (t (car entry)))))

(defmethod cache-get ((cache in-memory-ttl-cache) key &key)
  (%lookup cache key))

(defmethod cache-put ((cache in-memory-ttl-cache) key value &key ttl)
  (let ((exp (and ttl (+ (%now cache) ttl))))
    (setf (gethash key (in-memory-ttl-cache-table cache))
          (cons value exp))
    value))

(defmethod cache-delete ((cache in-memory-ttl-cache) key &key)
  (let ((present (nth-value 1 (gethash key (in-memory-ttl-cache-table cache)))))
    (remhash key (in-memory-ttl-cache-table cache))
    (and present t)))

(defmethod cache-incr ((cache in-memory-ttl-cache) key &key (delta 1))
  (let* ((cur (%lookup cache key))
         (n (cond
              ((null cur) 0)
              ((integerp cur) cur)
              ((and (stringp cur) (every (lambda (c)
                                           (or (digit-char-p c)
                                               (char= c #\-)))
                                         cur))
               (parse-integer cur))
              (t (error 'cache-error :key key
                        :message (format nil "not an integer: ~s" cur))))))
    (cache-put cache key (+ n delta))))

(defmethod cache-cas ((cache in-memory-ttl-cache) key expected new &key ttl)
  (let ((actual (%lookup cache key)))
    (if (equal actual expected)
        (cache-put cache key new :ttl ttl)
        (restart-case
            (error 'cache-cas-mismatch
                   :key key :expected expected :actual actual)
          (use-value (value)
            :report "Use a supplied value (treat CAS as success)"
            value)))))
