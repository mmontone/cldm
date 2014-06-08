(in-package :cl-user)

(require :cldm)

(ql:quickload :com.dvlsoft.clon)
(ql:quickload :osicat)

(setq *load-verbose* nil)

(eval-when (:execute :load-toplevel :compile-toplevel)
  (com.dvlsoft.clon:nickname-package))

(defparameter +CLDM-version+ "0.0.1")

(defparameter +commands+
  (list
   ;; init command
   (cons "init"
	 (clon:defsynopsis (:make-default nil :postfix "PROJECT-NAME [OPTIONS]")
	   (text :contents "Initialize a basic cld file in the current directory.")
	   (flag :short-name "h" :long-name "help"
		 :description "Print this help and exit.")
	   (switch :short-name "f" :long-name "force"
		   :description "Force cld file creation")
	   (stropt :long-name "project-name"
		   :argument-name "PROJECT-NAME"
		   :argument-type :optional
		   :default-value ""
		   :description "The project name")
	   (stropt :long-name "cld"
		   :argument-name "CLD"
		   :default-value ""
		   :argument-type :optional
		   :description "The project cld address")
	   (stropt :long-name "description"
		   :argument-name "DESCRIPTION"
		   :default-value ""
		   :argument-type :optional
		   :description "The project description")
	   (stropt :long-name "author"
		   :argument-name "AUTHOR"
		   :default-value ""
		   :argument-type :optional
		   :description "The project author")))
   ;; install command
   (cons "install"
	 (clon:defsynopsis (:make-default nil)
	   (text :contents "Install the CLDM project dependencies.")
	   (flag :short-name "h" :long-name "help"
		 :description "Print this help and exit.")
	   (flag :short-name "d" :long-name "dry-run"
		 :description "Fake the install operation. List the libraries that would be installed")
	   (switch :long-name "lenient"
		   :default-value nil
		   :description "Allow some of the dependencies not to be installed.")))
   ;; update command
   (cons "update"
	 (clon:defsynopsis (:make-default nil)
	   (text :contents "Update the CLDM project dependencies to available latest versions.")
	   (flag :short-name "h" :long-name "help"
		 :description "Print this help and exit.")
	   (flag :short-name "d" :long-name "dry-run"
		 :description "Fake the update operation. List which libraries would be updated")
	   (switch :long-name "lenient"
		   :default-value nil
		   :description "Allow some of the dependencies not to be updated.")))))

(defun print-command-list ()
  (format nil "~{~A~^, ~}" (mapcar #'car +commands+)))

(defun find-command (name)
  (cdr (assoc name +commands+ :test #'string=)))

(clon:defsynopsis (:postfix "command [OPTIONS]")
  (text :contents (format nil "  ___ _    ___  __  __ 
 / __| |  |   \\|  \\/  |
| (__| |__| |) | |\\/| |
 \\___|____|___/|_|  |_|
                        

CLDM is a Common Lisp Dependency Manager.

Available commands: ~A

Use 'cldm <command> --help' to get command-specific help.
" (print-command-list)))	
  (flag :short-name "h" :long-name "help"
	:description "Print this help and exit.")
  (flag :short-name "v" :long-name "version"
	:description "Print the CLDM version")
  (switch :short-name "d" :long-name "debug"
	  :description "Turn debugging on or off."
	  :argument-style :on/off
	  :env-var "DEBUG"))

(defun main ()
  "Entry point for the standalone application."
  (clon:make-context)
  (cond ((or (clon:getopt :short-name "h")
	     (not (clon:cmdline-p)))
	 (clon:help))
	((clon:getopt :long-name "version")
	 (format "CLDM Common Lisp Dependency Manager version ~A" +CLDM-version+))
	(t
	 (unless (clon:remainder)
	   (format t "Missing command.~%")
	   (clon:exit 1))
	 (clon:make-context
	  :synopsis (let ((command-name (car (clon:remainder))))
		      (let ((command (find-command command-name)))
			(if command
			    command
			    (progn
			      (format t "Unknown command.~%")
			      (clon:exit 1)))))
	  :cmdline (clon:remainder))
	 (cond ((clon:getopt :short-name "h")
		(clon:help))
	       (t ;; Process the command
		(process-command (intern (string-upcase (clon:progname)) :keyword))))))
  (clon:exit))

(defun create-cld-template (project-name &rest keys &key cld description author dependencies interactive)
  (if interactive
      (apply #'create-cld-template-interactive project-name keys)
      (apply #'create-cld-template-batch project-name keys)))

(defun create-cld-template-interactive (project-name &key cld description author dependencies &allow-other-keys)
  (flet ((read-project-name ()
	   (format t "Project name [~A]:" project-name)
	   (let ((line (read-line)))
	     (format t "~%")
	     line))
	 (read-description ()
	   (format t "Description:")
	   (let ((line (read-line)))
	     (format t "~%")
	     line))
	 (read-cld ()
	   (format t "CLD:")
	   (let ((line (read-line)))
	     (format t "~%")
	     line))
	 (read-author ()
	   (format t "Author:")
	   (let ((line (read-line)))
	     (format t "~%")
	     line))
	 (read-dependencies ()
	   (format t "Enter dependencies.~%")
	   (let ((dependencies nil)
		 (continue t))
	     (loop while continue
		do
		  (progn
		    (format t "Library:")
		    (let ((library (read-line)))
		      (format t "~%")
		      (if (not (equalp library ""))
			  (progn
			    (let ((version (progn (format t "Version:")
						  (read-line))))
			      (format t "~%")
			      (push (cons library version) dependencies)))
					; else
			  (return)))))
	     dependencies)))
    (let ((final-project-name (let ((read-project-name (read-project-name)))
				(or
				 (and (not (equalp read-project-name ""))
				      read-project-name)
				 project-name)))
	  (final-description (or (not (equalp description ""))
				 (read-description)))
	  (final-cld (or (not (equalp cld ""))
			 (read-cld)))
	  (final-author (or (not (equalp author ""))
			    (read-author)))
	  (final-dependencies (or dependencies
				  (read-dependencies))))
      (create-cld-template-batch final-project-name
				 :cld final-cld
				 :description final-description
				 :author final-author
				 :dependencies final-dependencies))))

(defun create-cld-template-batch (project-name &key cld description author dependencies &allow-other-keys)
  `(cldm:deflibrary ,project-name
     :cld ,cld
     :description ,description
     :author ,author
     :dependencies ,dependencies))

(defgeneric process-command (command))

(defmethod process-command ((command (eql :init)))
  (let ((project-name (car (clon:remainder))))
    ;; Check that the project name was given
    (when (null project-name)
      (format t "Project name is missing.~%")
      (clon:exit 1))
    (let ((cld-filename (pathname (format nil "~A.cld" project-name))))
      (flet ((create-cld-file ()
	       (let ((cld-template
		      (create-cld-template-interactive
		       project-name
		       :cld (clon:getopt :long-name "cld")
		       :author (clon:getopt :long-name "author")
		       :description (clon:getopt :long-name "description"))))
		 (format t "~A~%" cld-template)
		 (format t "Create? [yes]")
		 (let ((answer (read-line)))
		   (when (or (equalp answer "")
			     (not (equalp answer "no")))
		     (with-open-file (f cld-filename :direction :output
					:if-exists :supersede
					:if-does-not-exist :create)
		       (format f "~A" cld-template)))))))

	;; If the cld file exists, error unless a force option was given
	(let ((cld-file (merge-pathnames cld-filename
					 (osicat:current-directory))))
	  (if (probe-file cld-file)
	      (if (not (clon:getopt :long-name "force"))
		  (progn
		    (format t "The cld file already exist. Use the --force option to overwrite.~%")
		    (clon:exit 1))
		  (create-cld-file))
	      (create-cld-file)))))))

(defmethod process-command ((command (eql :install)))
  (format t "Mode: ~A~%" (clon:getopt :long-name "lenient"))
  (print "Processing the install command"))

(defmethod process-command ((command (eql :update)))
  (format t "Mode: ~A~%" (clon:getopt :long-name "lenient"))
  (print "Processing the update command"))

(clon:dump "cldm" main)
