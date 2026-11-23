(in-package #:cache-protocol)

(defclass cache-backend () ())

(defvar *cache-backend* nil)

(defgeneric cache-get (cache key &key)
  (:documentation "Return the value for KEY, or NIL if missing/expired."))

(defgeneric cache-put (cache key value &key ttl)
  (:documentation "Store VALUE at KEY. TTL is seconds from now as a real (fractions
   allowed), or NIL (no expiry). The entry is gone once TTL has elapsed.
   → VALUE."))

(defgeneric cache-delete (cache key &key)
  (:documentation "Delete KEY. → T if a value was present."))

(defgeneric cache-incr (cache key &key delta)
  (:documentation "Atomically add DELTA (an integer, default 1) to an integer value.
   Missing key starts at 0; the entry keeps its TTL. A value that is not an
   integer (or integer text) signals CACHE-ERROR. → new integer."))

(defgeneric cache-cas (cache key expected new &key ttl)
  (:documentation "Atomic compare-and-set: if the current value equals EXPECTED, store
   NEW with TTL (NIL: no expiry). EXPECTED NIL matches a missing key.
   Mismatch → CACHE-CAS-MISMATCH with USE-VALUE restart."))
