(in-package :cldm)

(defstruct (pbo-constraint
	     (:print-function print-pbo-constraint))
  terms comparison result comment)

(defstruct optimization-function
  terms)

(defparameter *pbo-environment* nil)
(defparameter *constraint-variable-counter* 1)

(defun print-pbo-constraint (pbo-constraint stream depth)
  (format stream "[~{~A~} ~A ~A ~S]"
	  (pbo-constraint-terms pbo-constraint)
	  (pbo-constraint-comparison pbo-constraint)
	  (pbo-constraint-result pbo-constraint)
	  (pbo-constraint-comment pbo-constraint)))

(defun make-pbo-constraint* (terms comparison result &optional comment)
  (make-pbo-constraint :terms terms
		       :comparison comparison
		       :result result
		       :comment comment))

(defun gen-pbo-variable (thing)
  (if (assoc thing *pbo-environment* :test #'equalp)
      (cdr (assoc thing *pbo-environment* :test #'equalp))
      ;; else
      (let ((var (make-keyword (format nil "X~A"
				       *constraint-variable-counter* ))))
	(push (cons thing var) *pbo-environment*)
	(incf *constraint-variable-counter*)
	var)))

(defun encode-dependency (library-version dependency)
  (let* ((dependency-library (find-library (library-name dependency)))
	 (library-versions (find-library-versions dependency-library dependency)))
    (let ((terms (append
		  (loop for library-version in library-versions
		     collect `(+ 1 ,(gen-pbo-variable
				     (library-version-unique-name library-version))))
		  `((- 1 ,(gen-pbo-variable (library-version-unique-name library-version)))))))    
    (make-pbo-constraint* terms
			  '>= 0
			  (format nil "~A dependency: ~A"
				  (library-version-unique-name library-version)
				  (library-name dependency))))))

(defun encode-conflict (library-version-1 library-version-2)
  (make-pbo-constraint*
   `((+ 1 ,(gen-pbo-variable
	    (library-version-unique-name library-version-1)))
     (+ 1 ,(gen-pbo-variable
	    (library-version-unique-name library-version-2))))
   '<=
   1
   (format nil "Conflict between ~A and ~A"
	   (library-version-unique-name library-version-1)
	   (library-version-unique-name library-version-2))))

(defun encode-install (library-version)
  (make-pbo-constraint*
   `((+ 1 ,(gen-pbo-variable (library-version-unique-name library-version))))
   '>=
   1
   (format nil "Install ~A" (library-version-unique-name library-version))))

(defun encode-library-versions (library-versions)
  (let ((grouped-library-versions
	 (group-by 
	  library-versions
	  :key #'library-name
	  :test #'equalp)))
    (let ((pbo-constraints
	   (loop for library-versions-group in grouped-library-versions
		appending
		(loop for library-version in library-versions-group
		     collect (encode-library-version library-version)))))
      pbo-constraints)))

(defun encode-library-versions-conflicts (library-versions)
  (loop for library-version-1 in library-versions
       for library-version-2 in (cdr library-versions)
       when (and (equalp (library-name library-version-1)
			 (library-name library-version-2))
		 (version/== (version library-version-1)
			     (version library-version-2)))
       collect (encode-conflict library-version-1
				library-version-2)))  

(defun encode-library-version-dependencies (library-version)
  (let ((dependency-constraints
	 (loop for dependency in (dependencies library-version)
	    collect 
	      (encode-dependency library-version dependency))))
    dependency-constraints))

(defun encode-install-library-version (library-version library-versions-involved)
  (let ((install-constraint (encode-install library-version))
	(dependencies-constraints
	 (loop for library-version in library-versions-involved
	    appending (encode-library-version-dependencies library-version)))
	(conflicts-constraints (encode-library-versions-conflicts
				library-versions-involved)))
    (let ((all-constraints (append (list install-constraint)
				   dependencies-constraints
				   conflicts-constraints)))
      (values
       all-constraints
       *pbo-environment*
       *constraint-variable-counter*
       (length all-constraints)))))

(defun serialize-pbo-constraints (pbo-constraints stream)
  (loop for pbo-constraint in pbo-constraints
       do
       (progn
	 (serialize-pbo-constraint pbo-constraint stream)
	 (format stream "~%"))))

(defun serialize-pbo-constraint (pbo-constraint stream)
  (format stream "* ~A *~%" (pbo-constraint-comment pbo-constraint))
  (loop for term in (pbo-constraint-terms pbo-constraint)
       do (destructuring-bind (sign constant var) term
	      (format stream "~A~A ~A " sign constant
		      (string-downcase (symbol-name var)))))
  (format stream "~A ~A ;"
	  (pbo-constraint-comparison pbo-constraint)
	  (pbo-constraint-result pbo-constraint)))

(defun create-optimization-function (library-versions-involved)
  (flet ((sort-library-versions-by-freshness (library-versions)
	   (sort library-versions #'version> :key #'version)))
    (let ((grouped-library-versions
	   (mapcar #'sort-library-versions-by-freshness
		   (group-by library-versions-involved
			     :key #'library-name
			     :test #'equalp))))
      (loop for versions-group in grouped-library-versions
	 appending
	   (loop for library-version in versions-group
	      for wi = 0 then (1+ wi)
	      collect `(+ ,wi ,(gen-pbo-variable
				(library-version-unique-name library-version))))))))

(defun serialize-optimization-function (optimization-function stream)
  (loop for term in optimization-function
       do (destructuring-bind (sign constant var) term
	    (format stream "~A~A ~A " sign constant
		    (string-downcase (symbol-name var))))))

(defun pbo-solve-library-versions (library-version library-versions-involved)
  (let ((*pbo-environment* nil)
	(*constraint-variable-counter* 1))
    (multiple-value-bind (constraints pbo-environment
				      variables-number constraints-number)
	(encode-install-library-version library-version library-versions-involved)
      (let ((optimization-function
	     (create-optimization-function library-versions-involved)))
	(let ((pbo-file #p"/tmp/deps.pbo"))
	  (with-open-file (stream pbo-file
				  :direction :output
				  :if-does-not-exist :create
				  :if-exists :supersede)
	    (format stream "* #variable= ~A #constraint= ~A~%"
		    variables-number
		    constraints-number)
	    (format stream "min: ")
	    (serialize-optimization-function optimization-function stream)
	    (format stream " ;~%" )
	    (serialize-pbo-constraints constraints stream))
	  (multiple-value-bind (result error status)
	      (trivial-shell:shell-command
	       (format nil "/usr/bin/minisat+ ~A -v0" pbo-file))
	    (when (not (zerop status))
	      (error "Error executing /usr/bin/minisat+ ~A -v0" pbo-file))
	    (flet ((find-environment-library-version (var)
		     (rassoc var pbo-environment)))
	      (cl-ppcre:register-groups-bind (vars-string)
		  ("\v (.*)" result)
		(let ((vars (mapcar (compose #'find-environment-library-version
					     #'make-keyword
					     #'string-upcase)
				    (split-sequence:split-sequence #\  vars-string))))
		  vars)))))))))
