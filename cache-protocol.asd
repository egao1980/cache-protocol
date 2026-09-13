(defsystem "cache-protocol"
  :version "0.1.0"
  :description "CLOS cache protocol for cl-stack (get/put/delete/incr/cas + in-memory TTL)"
  :author "egao1980"
  :license "MIT"
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "conditions")
               (:file "protocol")
               (:file "memory"))
  :in-order-to ((test-op (test-op "cache-protocol/tests"))))

(defsystem "cache-protocol/tests"
  :depends-on ("cache-protocol" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "protocol-test")
               (:file "restarts-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
