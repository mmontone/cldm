(in-package :cl-user)

(setq *load-verbose* nil)

(require :cldm)
(require :com.dvlsoft.clon)
(require :trivial-backtrace)

(load (merge-pathnames "package.lisp" *load-pathname*))
(load (merge-pathnames "init.lisp" *load-pathname*))
(load (merge-pathnames "config.lisp" *load-pathname*))
(load (merge-pathnames "repository.lisp" *load-pathname*))
(load (merge-pathnames "cli.lisp" *load-pathname*))

(clon:dump "cldm" cldm.cli::main)
