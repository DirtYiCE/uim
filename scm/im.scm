;;; im.scm: Core IM management functions for uim
;;;
;;; Copyright (c) 2003-2006 uim Project http://uim.freedesktop.org/
;;;
;;; All rights reserved.
;;;
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions
;;; are met:
;;; 1. Redistributions of source code must retain the above copyright
;;;    notice, this list of conditions and the following disclaimer.
;;; 2. Redistributions in binary form must reproduce the above copyright
;;;    notice, this list of conditions and the following disclaimer in the
;;;    documentation and/or other materials provided with the distribution.
;;; 3. Neither the name of authors nor the names of its contributors
;;;    may be used to endorse or promote products derived from this software
;;;    without specific prior written permission.
;;;
;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS ``AS IS'' AND
;;; ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE
;;; FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
;;; DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
;;; OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
;;; HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
;;; LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
;;; OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
;;; SUCH DAMAGE.
;;;;

; Comment should be written in English, UTF-8.
;
(require "util.scm")
(require "i18n.scm")
(require "load-action.scm")

;; config
(define enable-im-switch #f)
(define default-im-name #f)

;; preedit attributes: should be moved to another file
(define preedit-none      0)
(define preedit-underline 1)
(define preedit-reverse   2)
(define preedit-cursor    4)
(define preedit-separator 8)
(define preedit-attr?
  (lambda (attr)
    (memv attr (list preedit-none
		     preedit-underline
		     preedit-reverse
		     preedit-cursor
		     preedit-separator))))

;;
;; im-management
;;
(define im-list ())

;; enabled-im-list cannot be changed once libuim has been
;; initialized. This limitation may be removed after uim 0.4.6.
;;   -- YamaKen 2005-01-25
(define enabled-im-list ())
(define system-available-im-list ())

(define-record 'im
  (list
   (list 'name                        #f)  ;; must be first member
   (list 'lang                        "")
   (list 'encoding                    "")
   (list 'name-label                  "")  ;; under discussion
   (list 'short-desc                  "")
   (list 'init-arg                    #f)
   (list 'init-handler                list)
   (list 'release-handler             list)
   (list 'mode-handler                list)
   (list 'key-press-handler           list)
   (list 'key-release-handler         list)
   (list 'reset-handler               list)
   (list 'get-candidate-handler       list)
   (list 'set-candidate-index-handler list)
   (list 'prop-activate-handler       list)
   (list 'module-name                 "")))

(define im-custom-set-handler
  (lambda (im)
    (if (symbol-bound? 'custom-prop-update-custom-handler)
	custom-prop-update-custom-handler
	list)))

;; Invoking this procedure causes inconsistency between im-list and
;; corresponding IM management entity in C-side
;; (uim_im_array). uim-im-switcher may show IM list in strange
;; order. This inconsistency problem is also preventing IM removal
;; feature implementation. We should resolve it after uim 0.4.6.
;;   -- YamaKen 2005-01-25
(define normalize-im-list
  (lambda ()
    (let ((ordinary-im-list (alist-delete 'direct im-list eq?))
	  (direct-im (retrieve-im 'direct)))
      (if direct-im
	  (set! im-list (cons direct-im
			      ordinary-im-list))))))

;; TODO: rewrite test
;; accepts overwrite register
;; returns initial register or not
(define register-im
  (lambda (name lang encoding name-label short-desc init-arg init release
		mode key-press key-release reset
		get-candidate set-candidate-index prop)
    (and (or (null? enabled-im-list)  ;; bootstrap
	     (memq name enabled-im-list)
	     (eq? name 'direct))  ;; direct IM must always be enabled
	 (let ((im (im-new name lang encoding name-label short-desc
			   init-arg init release
			   mode key-press key-release reset
			   get-candidate set-candidate-index prop
			   currently-loading-module-name)))
	   (set! im-list (alist-replace im im-list))
	   (normalize-im-list)
	   (im-register-im name lang encoding short-desc)))))

;; called from C
(define uim-get-im-short-desc
  (lambda (name)
    (let ((im (retrieve-im name)))
      (im-return-str (or (and im
			      (im-short-desc im))
			 "-")))))

;; strictly find out im by name
(define retrieve-im
  (lambda (name)
    (and name
	 (let ((im (assq name im-list)))
	   im))))

(define default-im-for-debug
  (lambda ()
    (and (feature? 'debug)
	 (let* ((str (getenv "UIM_IM_ENGINE"))
		(sym (and str
			  (string->symbol str))))
	   (retrieve-im sym)))))

(define find-im-for-locale
  (lambda (localestr)
    (let* ((lang (locale-zh-awared-lang (locale-new localestr)))
	   (ims-for-lang (filter (lambda (im)
				   (langgroup-covers? (im-lang im)
						      lang))
				 im-list))
	   (preference-ordered (and (not (null? ims-for-lang))
				    (reverse ims-for-lang))))
      (and (not (null? preference-ordered))
	   (car preference-ordered)))))

(define find-default-im
  (lambda (localestr)
    (or (default-im-for-debug)
	(retrieve-im default-im-name)
	(find-im-for-locale localestr))))

;; find most suitable im by im-name and lang
(define find-im
  (lambda (name localestr)
    (or (retrieve-im name)
	(find-default-im localestr))))

;; called from uim_get_default_im_name()
(define uim-get-default-im-name
  (lambda (localestr)
    (let ((name (im-name (find-default-im localestr))))
      (im-return-str (symbol->string name)))))

;; called from uim_get_im_name_for_locale()
(define uim-get-im-name-for-locale
  (lambda (localestr)
    (let ((name (im-name (find-im-for-locale localestr))))
      (im-return-str (symbol->string name)))))

;;
;; im-switching
;;
(define next-im
  (lambda (name)
    (let* ((im-names (map car im-list))
	   (im-rest (memq name im-names)))
      (or (and im-rest
               (not (null? im-rest))
	       (cadr im-rest))
	  (car im-names)))))

(define switch-im
  (lambda (id name)
    (uim-switch-im id (next-im name))))

;; im-toggle
(define toggle-im-preserved-im #f)
(define toggle-im-preserved-widget-states '())
(define toggle-im-alt-preserved-widget-states '())

(define toggle-im
  (lambda (id name)
    (let ((widget-states (context-current-widget-states (find-context id))))
      (if (eq? name toggle-im-alt-im)
	  (begin
	    (set! toggle-im-alt-preserved-widget-states widget-states)
	    (if toggle-im-preserved-im
		(begin
		  (uim-switch-im id toggle-im-preserved-im)
		  (context-update-widget-states!
		   (find-context id)
		   toggle-im-preserved-widget-states))))
	  (begin
	    (set! toggle-im-preserved-im name)
	    (set! toggle-im-preserved-widget-states widget-states)
	    (uim-switch-im id toggle-im-alt-im)
	    (context-update-widget-states! (find-context id)
	    			  toggle-im-alt-preserved-widget-states))))))

;;
;; context-management
;;
(define context-list ())

(define context-rec-spec
  '((id      #f)  ;; must be first member
    (im      #f)
    (widgets ())))  ;; may be renamed
(define-record 'context context-rec-spec)

(define find-context
  (lambda (id)
    (assv id context-list)))

(define remove-context
  (lambda (id)
    (set! context-list
	  (filter (lambda (c)
		    (not (= (context-id c)
			    id)))
		  context-list))))

(define register-context
  (lambda (c)
    (set! context-list
	  (cons c context-list))))

(define create-context
  (lambda (id lang name)
    (let* ((im (find-im name lang))
	   (arg (and im (im-init-arg im))))
      (if (find-context id)
	  (release-context id))
      (im-set-encoding id (im-encoding im))
      (update-style uim-color-spec (symbol-value uim-color))
      (let* ((handler (im-init-handler im))
	     (c (handler id im arg))
	     (widget-ids (context-widgets c)))
	(context-init-widgets! c widget-ids)
	(register-context c)))))

(define release-context
  (lambda (id)
    (invoke-handler im-release-handler id)
    (remove-context id)
    #f))

;;
;; dispatchers
;;
(define invoke-handler
  (lambda args
    (let* ((handler-reader (car args))
	   (id (cadr args))
	   (c (find-context id))
	   (handler-args (cons c (cddr args)))
	   (im (and c (context-im c)))
	   (handler (and im (handler-reader im)))
	   (result (and handler
			(apply handler handler-args))))
      (context-update-widgets c)
      result)))

;; Don't discard unnecessary key events. They are necessary for
;; proper GUI widget handling. More correction over entire uim
;; codes is needed.
(define key-press-handler
  (lambda (id key state)
    (let* ((c (find-context id))
	   (im (and c (context-im c))))
      (cond
       ((and enable-im-toggle?
	     (toggle-im-key? key state))
	(toggle-im id (im-name im)))
       ((and enable-im-switch
	     (switch-im-key? key state))
	(switch-im id (im-name im)))
       ((modifier-key? key state)
	;; don't discard modifier press/release edge for apps
	(im-commit-raw c))
       (else
	(invoke-handler im-key-press-handler id key state))))))

(define key-release-handler
  (lambda (id key state)
    (let ((c (find-context id)))
      (cond
       ((modifier-key? key state)
	;; don't discard modifier press/release edge for apps
	(im-commit-raw c))
       (else
	(invoke-handler im-key-release-handler id key state))))))

(define reset-handler
  (lambda (id)
    (invoke-handler im-reset-handler id)))

(define mode-handler
  (lambda (id mode)
    (invoke-handler im-mode-handler id mode)))

(define prop-activate-handler
  (lambda (id message)
    (invoke-handler im-prop-activate-handler id message)))

(define custom-set-handler
  (lambda (id custom-sym custom-val)
    (invoke-handler im-custom-set-handler id custom-sym custom-val)))

(define get-candidate
  (lambda (id idx accel-enum-hint)
    (im-return-str-list (invoke-handler im-get-candidate-handler
					id idx accel-enum-hint))))

(define set-candidate-index
  (lambda (id idx)
    (invoke-handler im-set-candidate-index-handler id idx)))
