(in-package :cldm)

(defparameter *libraries-directory*
  (pathname "~/.cldm/cache/libraries/"))

(defparameter *standard-cldm-repo*
  `(make-instance 'cached-http-cld-repository
                  :name "cldm-repo"
                  :url "http://mmontone.github.io/cldm-repo/cld"
		  :cache-directory (pathname "~/.cldm/cache/cld-repositories/cldm-repo/")))

(defparameter *cld-repositories* (list *standard-cldm-repo*))

(defparameter *address-cache-operation* :symlink "What to do when caching a local file system directory. Can be either :symlink or :copy (copy the directory recursively). Default is :symlink")

(defparameter *verbose-mode* t)

(defparameter *solving-mode* :strict "One of :strict, :lenient. If :strict, errors are signaled if a cld cannot be found, or a dependency version is not specified. If :lenient, signal warnings and try to solve dependencies loading latest versions and the like.")

(defparameter *clean-asdf-environment* nil "If T, load libraries in a clean ASDF environment")

(defparameter *minisat+-binary* "/usr/bin/minisat+"
  "minisat+ binary for PBO solving")

(defparameter *local-libraries-directory* (merge-pathnames (pathname ".cldm/")
							   (osicat:current-directory)))

;; Configuration files

(defparameter *global-config-file* #p"/etc/cldm/config")
(defparameter *user-config-file* #p"~/.cldm/config")
(defparameter *local-config-file* (merge-pathnames (pathname ".cldm/config")
						   (osicat:current-directory)))

(defun call-with-libraries-directory (pathname function)
  (let ((*libraries-directory* pathname))
    (funcall function)))

(defmacro with-libraries-directory (pathname &body body)
  `(call-with-libraries-directory
    ,pathname
    (lambda ()
      ,@body)))

(defun call-with-cld-repositories (repositories function)
  (let ((*cld-repositories* repositories))
    (funcall function)))

(defmacro with-cld-repositories (repositories &body body)
  `(call-with-cld-repositories
    (list ,@repositories)
    (lambda ()
      ,@body)))

(defun read-config-file (pathname)
  (read-from-string (file-to-string pathname) nil))

(defun read-config (scope)
  (let ((config-file (ecase scope
		       (:local *local-config-file*)
		       (:user *user-config-file*)
		       (:global *global-config-file*))))
    (read-config-file config-file)))

(defun load-config-file (pathname)
  (when (probe-file pathname)
    (let ((configuration (read-config-file pathname)))
      (when configuration
	(awhen (getf configuration :minisat+-binary)
	  (setf *minisat+-binary* it))
	(awhen (getf configuration :libraries-directory)
	  (setf *libraries-directory* (eval it)))
	(awhen (getf configuration :verbose-mode)
	  (setf *verbose-mode* it))
	(awhen (getf configuration :local-libraries-directory)
	  (setf *local-libraries-directory*
		(merge-pathnames (pathname it)
				 (osicat:current-directory))))
	(awhen (getf configuration :address-cache-operation)
	  (setf *address-cache-operation* it))
	(awhen (getf configuration :set-repositories)
	  (setf *cld-repositories*
		(loop for repository-spec in it
		   collect
		     (apply #'make-instance it))))
	(awhen (getf configuration :add-repositories)
	  (setf *cld-repositories*
		(append
		 (loop for repository-spec in it
		    collect
		      (apply #'make-instance it))
		 *cld-repositories*)))))))

(defun dump-config (config scope)
  (let ((config-file (ecase scope
		       (:local *local-config-file*)
		       (:user *user-config-file*)
		       (:global *global-config-file*))))
    (dump-config-to-file config config-file)))
  
(defun dump-config-to-file (config pathname)
  (with-open-file (f pathname
		     :direction :output
		     :if-exists :supersede
		     :if-does-not-exist :create)
    (format f "~S" config)))

(defun load-cldm-config ()
  (load-config-file *global-config-file*)
  (load-config-file *user-config-file*)
  (load-config-file *local-config-file*))

(defun set-config-var (keyword type value scope &optional (reload t))
  (assert (typep value type))
  (let ((config (read-config scope)))
    (setf (getf config keyword)
	  value)
    (dump-config config scope)
    (when reload
      (load-cldm-config))))

(defun unset-config-var (keyword scope &optional (reload t))
    (let ((config (read-config scope)))
      (remf config keyword)
      (dump-config config scope)
      (when reload
	(load-cldm-config))))

(defun get-config-var (keyword scope)
  (let ((config (read-config scope)))
    (getf config keyword)))

(defun config-set-libraries-directory (libraries-directory scope &optional (reload t))
  (set-config-var :libraries-directory 'pathname libraries-directory scope reload))

(defun config-set-local-libraries-directory (local-libraries-directory scope &optional (reload t))
  (set-config-var :local-libraries-directory 'pathname local-libraries-directory scope reload))

(defun config-set-verbose (verbose scope &optional (reload t))
  (set-config-var :verbose 'boolean verbose scope reload))

(defun config-set-minisat+-binary (minisat scope &optional (reload t))
  (set-config-var :minisat+-binary 'pathname minisat scope reload))

(defun config-set-repositories (repositories scope &optional (reload t))
  (set-config-var :repositories 'cons repositories scope reload))

(defun config-add-repository (repository scope &optional (reload t))
  (let ((repositories (get-config-var :repositories scope)))
    (push repository repositories)
    (set-config-var :repositories 'cons repositories scope reload)))

(defun config-remove-repository (name scope &optional (reload t))
  (let ((repositories (get-config-var :repositories scope)))
    (setf repositories (remove name repositories
			       :key #'car
			       :test #'equalp))
    (set-config-var :repositories 'cons repositories scope reload)))

(defun config-append-repository (repository scope &optional (reload t))
  (let ((repositories (get-config-var :add-repositories scope)))
    (push repository repositories)
    (set-config-var :add-repositories 'cons repositories scope reload)))