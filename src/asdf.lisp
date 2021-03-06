(defpackage :cldm.asdf
  (:use :cl :cldm :semver)
  (:export #:deflibrary-file-from-asdf-system
	   #:deflibrary-from-asdf-system))
	   
(in-package :cldm.asdf)

(defun deflibrary-file-from-asdf-system (asdf-system cld pathname &key (if-exists :supersede)
								    repositories)
  (with-open-file (f pathname
		     :direction :output
		     :if-exists if-exists
		     :if-does-not-exist :create)
    (deflibrary-from-asdf-system asdf-system cld f :repositories repositories)))

(defmethod deflibrary-from-asdf-system ((asdf-system symbol) cld stream &key repositories)
  (deflibrary-from-asdf-system (asdf:find-system asdf-system) cld stream :repositories repositories))

(defmethod deflibrary-from-asdf-system ((asdf-system string) cld stream &key repositories)
  (deflibrary-from-asdf-system (asdf:find-system asdf-system) cld stream :repositories repositories))

(defmethod deflibrary-from-asdf-system ((asdf-system asdf:system) cld stream &key repositories)
  (format stream ";;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: CL-USER; Base: 10 -*-~%~%")
  (format stream "~S" (make-cld-library-form asdf-system
					     :cld cld
					     :repositories repositories)))

(defun make-cld-library-form (asdf-system &key cld repositories)
  (let ((system-name (slot-value asdf-system 'asdf::name)))
    `(cldm:deflibrary ,(intern (string-upcase system-name))
       :cld ,cld
       ,@(when (asdf:system-description asdf-system)
	       (list :description (asdf:system-description asdf-system)))
       ,@(when (asdf:system-author asdf-system)
	       (list :author (asdf:system-author asdf-system)))
       ,@(when (asdf:system-maintainer asdf-system)
	       (list :maintainer (asdf:system-maintainer asdf-system)))
       ,@(when (asdf:system-licence asdf-system)
	       (list :licence (asdf:system-licence asdf-system)))
					;,@(when (asdf:system-homepage asdf-system)
					;(list :homepage (asdf:system-homepage asdf-system)))
					;,@(when (asdf:system-mailto asdf-system)
					;(list :mailto (asdf:system-mailto asdf-system)))
       :versions
       ((:version ,(or (and (asdf:component-version asdf-system)
			    (ignore-errors (read-version-from-string (asdf:component-version asdf-system)))
			    (asdf:component-version asdf-system))			    
		       "latest")
		  :repositories ,(if repositories
				     repositories
				     (list (list :default
						 (list :directory
						       (asdf:system-source-directory asdf-system)))))
		  :depends-on
		  ,(loop for dependency in (asdf:component-sideway-dependencies asdf-system)
		      collect (cond
				((or (symbolp dependency)
				     (stringp dependency))
				 dependency)
				((and (listp dependency)
				      (equalp (first dependency) :version))
				 (list (second dependency) ;; The system name
				       :version (third dependency))) ;; The version
				(t (error "Error parsing asdf dependency ~A" dependency)))))))))
