;;; test-yeah-shell.el --- ERT tests for yeah-shell -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'yeah-shell)

(ert-deftest yeah-shell-history-add-and-list ()
  "Adding to the history records inputs."
  (let ((yeah-shell--history (make-ring 200)))
    (yeah-shell-history-add "first")
    (yeah-shell-history-add "second")
    (let ((hist (yeah-shell-history)))
      ;; ring-elements returns newest-first; we don't care about
      ;; the order, only that the elements are present.
      (should (= 2 (length hist)))
      (should (member "first" hist))
      (should (member "second" hist)))))

(ert-deftest yeah-shell-history-add-skips-empty ()
  "Empty strings and nil are not recorded."
  (let ((yeah-shell--history (make-ring 200)))
    (yeah-shell-history-add "")
    (yeah-shell-history-add nil)
    (should (= 0 (yeah-shell-history-length)))))

(ert-deftest yeah-shell-history-clear-empties ()
  "Clear drops all entries."
  (let ((yeah-shell--history (make-ring 200)))
    (yeah-shell-history-add "x")
    (yeah-shell-history-clear)
    (should (= 0 (yeah-shell-history-length)))))

(ert-deftest yeah-shell-history-add-bounded-by-ring ()
  "The history ring is bounded; old entries drop as new ones come in."
  (let ((yeah-shell--history (make-ring 3)))
    (dotimes (i 5)
      (yeah-shell-history-add (format "msg-%d" i)))
    (let ((hist (yeah-shell-history)))
      (should (= 3 (length hist)))
      ;; Oldest two ("msg-0", "msg-1") are dropped; we keep msg-2..msg-4.
      (should-not (member "msg-0" hist))
      (should-not (member "msg-1" hist))
      (should (member "msg-2" hist))
      (should (member "msg-3" hist))
      (should (member "msg-4" hist)))))

(ert-deftest yeah-shell-format-prompt ()
  "The prompt string is exactly the configured value."
  (should (string= "yeah> " (yeah-shell--format-prompt))))

(ert-deftest yeah-shell-ensure-buffer-creates-on-demand ()
  "The first call to `yeah-shell--ensure-buffer' creates the buffer."
  (let ((name "*yeah-shell-test-isolation*"))
    (setq yeah-shell--buffer-name name)
    (unwind-protect
        (progn
          (should-not (get-buffer name))
          (let ((buf (yeah-shell--ensure-buffer)))
            (should (bufferp buf))
            (should (eq (get-buffer name) buf))))
      (when (get-buffer name)
        (kill-buffer name))
      (setq yeah-shell--buffer-name "*yeah-shell*"))))

(ert-deftest yeah-shell-send-input-appends-to-history ()
  "`yeah-shell-send-input' adds the input to the history."
  (let ((yeah-shell--history (make-ring 200))
        (yeah-shell--buffer-name "*yeah-shell-send-input-test*"))
    (unwind-protect
        (progn
          (yeah-shell-send-input "hello world")
          (should (= 1 (yeah-shell-history-length)))
          (let ((hist (yeah-shell-history)))
            (should (member "hello world" hist))))
      (when (get-buffer yeah-shell--buffer-name)
        (kill-buffer yeah-shell--buffer-name))
      (yeah-shell-history-clear)
      (setq yeah-shell--buffer-name "*yeah-shell*"))))

(provide 'test-yeah-shell)
;;; test-yeah-shell.el ends here
