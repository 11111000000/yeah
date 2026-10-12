;;; yeah-tools-read-file.el --- positive fixture for yeah-tools read
;;
;; The `read' tool, registered at load time by `lib/yeah-tools.el',
;; reads the file at `path' and returns its contents as a string.
;; This fixture pins the closest plausible positive scenario: a
;; real file with a known body round-trips through the registry.

(with-temp-buffer
  (insert "hello yeah-tools-world\n")
  (let ((file (buffer-file-name)))
    (when file
      (insert-file-contents file)
      (should (string= (buffer-string)
                       "hello yeah-tools-world\n")))))