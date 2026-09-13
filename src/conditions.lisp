(in-package #:cache-protocol)

(define-condition cache-error (error)
  ((message :initarg :message :reader cache-error-message :initform nil)
   (key :initarg :key :reader cache-error-key :initform nil))
  (:report (lambda (c s)
             (format s "cache error~@[ (~s)~]~@[: ~a~]"
                     (cache-error-key c)
                     (cache-error-message c)))))

(define-condition cache-cas-mismatch (cache-error)
  ((expected :initarg :expected :reader cache-cas-mismatch-expected :initform nil)
   (actual :initarg :actual :reader cache-cas-mismatch-actual :initform nil))
  (:report (lambda (c s)
             (format s "cache CAS mismatch for ~s (expected ~s, actual ~s)~@[: ~a~]"
                     (cache-error-key c)
                     (cache-cas-mismatch-expected c)
                     (cache-cas-mismatch-actual c)
                     (cache-error-message c)))))
