(defpackage #:cache-protocol
  (:use #:cl)
  (:nicknames #:stack-cache)
  (:export #:cache-error
           #:cache-error-message
           #:cache-error-key
           #:cache-cas-mismatch
           #:cache-cas-mismatch-expected
           #:cache-cas-mismatch-actual

           #:cache-backend
           #:*cache-backend*

           #:cache-get
           #:cache-put
           #:cache-delete
           #:cache-incr
           #:cache-cas

           #:in-memory-ttl-cache
           #:make-in-memory-ttl-cache
           #:use-in-memory-ttl-cache
           #:cache-clock
           #:cache-connection-error
           #:cache-connection-error-cause
           #:monotonic-seconds))

(in-package #:cache-protocol)
