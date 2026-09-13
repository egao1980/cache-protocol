(in-package #:cache-protocol)

(defclass cache-backend () ())

(defvar *cache-backend* nil)

(defgeneric cache-get (cache key &key)
  (:documentation "Return the value for KEY, or NIL if missing/expired."))

(defgeneric cache-put (cache key value &key ttl)
  (:documentation "Store VALUE at KEY. TTL is seconds from now, or NIL (no expiry).
   → VALUE."))

(defgeneric cache-delete (cache key &key)
  (:documentation "Delete KEY. → T if a value was present."))

(defgeneric cache-incr (cache key &key delta)
  (:documentation "Atomically add DELTA (default 1) to an integer value.
   Missing key starts at 0. → new integer."))

(defgeneric cache-cas (cache key expected new &key ttl)
  (:documentation "Compare-and-set: if current value equals EXPECTED, store NEW.
   Mismatch → CACHE-CAS-MISMATCH with USE-VALUE restart."))
