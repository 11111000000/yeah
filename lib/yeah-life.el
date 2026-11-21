;;; yeah-life.el --- the life of a child process -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; A child that waits for something must not outlive the process that
;; started it.  A child that reads a pipe knows when its parent is gone:
;; the pipe is closed and the read ends.  A child that serves on a socket
;; has no pipe to wait for.  It waits for a client that may never come,
;; and when the parent dies the child stays behind and holds the socket.
;;
;; The measurement of 2026-11-18: a check of the repository was killed by
;; the timeout of the gate, and the server of the check stayed behind.
;; The server of a check that ends normally leaves with it; the server of
;; a check that was killed does not.  The life of such a server is a
;; socket of its own.
;;
;; The owner listens on that socket and the child connects to it.  The
;; connection is a pipe of the kernel: when the owner dies -- by any
;; means, a clean exit, a signal, a crash -- the kernel closes it, the
;; child reads the end of it, and the child ends.  The owner does not
;; have to remember to stop the child: the child watches for its owner.
;;
;; The socket lives in a private directory and its name carries the pid
;; of the owner, so two owners never share a socket, and a socket left
;; behind by a dead owner is swept when the next owner starts.
;;
;; The owner of a socket is alive when the state of its process says so
;; (`lib/yeah-proc.el').  A zombie owner is dead: it has died already
;; and waits to be reaped, it holds nothing and serves nobody.  Its
;; socket is swept, and the socket of a zombie is never the reason why a
;; service cannot start.

;;; Code:

(require 'cl-lib)
(require 'files)
(require 'yeah-proc)

(defgroup yeah-life nil
  "The life of a child process that waits for something."
  :group 'yeah)

(defun yeah-life--tag (tag)
  "Return TAG as a word that a file name can carry."
  (replace-regexp-in-string "[^A-Za-z0-9]+" "-" (format "%s" tag)))

(defun yeah-life-socket-path (directory tag)
  "Return the path of the life socket of TAG in DIRECTORY.
The name carries the pid of this process: two owners never share a
socket, and a socket left behind by a dead owner is a file of a pid
that is not alive any more."
  (expand-file-name (format "yeah-life-%s-%d.sock"
                            (yeah-life--tag tag)
                            (emacs-pid))
                    directory))

(defun yeah-life--pid-of (file)
  "Return the pid of the owner of the life socket FILE, or nil."
  (let ((name (file-name-nondirectory file)))
    (when (string-suffix-p ".sock" name)
      (let ((fields (split-string (substring name 0 -5) "-")))
        (when (and fields (string-match-p "\\`[0-9]+\\'" (car (last fields))))
          (string-to-number (car (last fields))))))))

(defun yeah-life-directory ()
  "Return the user-private directory that holds the life sockets.
Anyone who can connect to a life socket can end the life of a child, so
the directory is never world-writable: it goes under XDG_RUNTIME_DIR when
there is one, else under a directory of this user with mode 0700."
  (let ((dir (if-let ((runtime (getenv "XDG_RUNTIME_DIR")))
                 (expand-file-name "yeah" runtime)
               (expand-file-name (format "yeah-%d" (user-uid))
                                 (or (getenv "TMPDIR") "/tmp")))))
    (unless (file-directory-p dir)
      (make-directory dir t)
      (set-file-modes dir #o700))
    dir))

(defvar yeah-life--owned nil
  "The path of the life socket this process listens on, or nil.")

(defun yeah-life-adopt (path)
  "Listen on the life socket PATH and return PATH.
The process becomes the owner of the socket: the children that connect
to it end when this process ends.  A socket left behind by a dead owner
is removed first, because a file left on disk keeps the next owner from
binding it; a socket of a living owner is never touched, because the life
of a socket is not worth the risk of killing a living owner."
  (when (file-exists-p path)
    (let ((owner (yeah-life--pid-of path)))
      ;; The owner lives when the state of its process says so.  A
      ;; zombie owner is dead, and the socket of a dead owner is taken
      ;; away: a socket of a zombie must not keep a service from
      ;; starting.
      (if (and owner (yeah-proc-alive-p (yeah-proc-state owner)))
          (error "yeah-life-adopt: the life socket %s belongs to a living process"
                 path)
        (ignore-errors (delete-file path)))))
  (make-directory (file-name-directory path) t)
  (yeah-life-socket-create path)
  (setq yeah-life--owned path)
  path)

(defun yeah-life-adopt-from-environment ()
  "Adopt the life socket named by YEAH_LIFE_SOCKET and return its path.
Return nil when the environment names no socket, or when this process
already owns that socket: a process that owns the socket would not watch
its own life, it would hold it."
  (let ((path (getenv "YEAH_LIFE_SOCKET")))
    (when (and path (not (equal path yeah-life--owned)))
      (yeah-life-adopt path))))

(defun yeah-life-inherited-path ()
  "Return the life socket of the owner of this process, or nil.
The owner names the socket in the environment variable YEAH_LIFE_SOCKET,
and every child inherits the name.  The path is nil when this process
owns that socket itself, and nil when the socket is gone: an owner that
is gone cannot be watched any more."
  (let ((path (getenv "YEAH_LIFE_SOCKET")))
    (when (and path
               (not (equal path yeah-life--owned))
               (file-exists-p path))
      path)))

(defun yeah-life-socket-sweep (directory)
  "Remove the life sockets in DIRECTORY whose owner is dead.
A socket of a living owner stays: the life of a socket is not worth the
risk of killing a living owner.  On a platform without /proc nothing is
removed: the life of a socket is not worth the risk of killing a living
owner."
  (when (file-directory-p "/proc")
    (dolist (file (file-expand-wildcards
                   (expand-file-name "yeah-life-*.sock" directory)))
      (let ((pid (yeah-life--pid-of file)))
        (when (and pid (not (yeah-proc-alive-p (yeah-proc-state pid))))
          (ignore-errors (delete-file file)))))))

;;;###autoload
(defun yeah-life-socket-create (path)
  "Listen on the life socket PATH and return the server process.
The process accepts the connection of the child that watches this
socket.  The child ends when the socket ends, and the socket ends when
this process ends."
  (when (file-exists-p path)
    ;; The name of the socket carries the pid of this process, so a file
    ;; at this path is a leftover of an earlier life of this process.
    (ignore-errors (delete-file path)))
  (make-network-process
   :name "yeah-life"
   :server t
   :family 'local
   :service path
   :noquery t
   :filter (lambda (_connection _chunk) nil)
   :sentinel
   (lambda (connection _event)
     (when (memq (process-status connection) '(closed failed exit))
       (ignore-errors (delete-process connection))))))

;;;###autoload
(defun yeah-life-socket-connect (path)
  "Connect to the life socket PATH and return the connection process.
Return nil when the socket is gone: the owner that held it is dead, and
a child without an owner has nothing to serve."
  (condition-case nil
      (make-network-process
       :name "yeah-life-watch"
       :family 'local
       :service path
       :noquery t
       :filter (lambda (_connection _chunk) nil))
    (error nil)))

;;;###autoload
(defun yeah-life-alive-p (connection)
  "Return non-nil when the owner of CONNECTION is still alive."
  (and connection (process-live-p connection)))

;;;###autoload
(defun yeah-life-socket-close (path)
  "Remove the file of the life socket PATH."
  (when (and path (file-exists-p path))
    (ignore-errors (delete-file path)))
  nil)

(provide 'yeah-life)

;;; yeah-life.el ends here
