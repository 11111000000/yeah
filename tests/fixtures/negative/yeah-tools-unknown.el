;;; yeah-tools-unknown.el --- negative fixture for yeah-tools
;;
;; Calling a tool name that is not registered raises `user-error'.
;; This fixture pins the closest plausible negative scenario:
;; looking up a tool id that does not exist in the registry.

(condition-case nil
    (let ((result
           (yeah-tools-call "definitely-not-a-tool" nil)))
      (error (format "fixture name conflict: %S" result))
      (signal 'user-error '("yeah-tools-call: unknown tool name"))
      (error "yeah-tools-call should have signalled user-error"))
  (user-error
   (message "negative fixture ok: unknown tool name is rejected")))