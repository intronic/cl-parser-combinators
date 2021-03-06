(in-package :parser-combinators)

;;; operate on list of tokens

(defclass parser-possibility ()
  ((tree :accessor tree-of :initarg :tree :initform nil)
   (suffix :accessor suffix-of :initarg :suffix :initform nil)))


;;; lazy results

;;; continuation is a thunk returning parser-possibility or nil

(defclass parse-result-store ()
  ((storage      :accessor storage-of      :initarg :storage      :initform (make-array 3 :initial-element nil))
   (counter      :accessor counter-of      :initarg :counter :initform 0)
   (continuation :accessor continuation-of :initarg :continuation :initform (constantly nil))))

(defclass parse-result ()
  ((store   :accessor store-of   :initarg :store :initform nil)
   (current :accessor current-of :initarg :current :initform -1)))

(defgeneric nth-result (n parse-result-store)
  (:method (n (parse-result-store null))
    (declare (ignore n parse-result-store))
    nil)
  (:method (n (parse-result parse-result))
    (nth-result n (store-of parse-result)))
  (:method (n (parse-result-store parse-result-store))
    (with-accessors ((storage storage-of)
                     (counter counter-of)
                     (continuation continuation-of))
        parse-result-store
      (if (< n counter)
          (svref storage n)
          (when continuation
            (iter (for i from counter to n)
                  (for next-result = (funcall continuation))
                  (when (= i (length storage))
                    (let ((old-storage storage))
                      (setf storage (make-array (* 2 (length storage)) :initial-element nil))
                      (setf (subseq storage 0 i) old-storage)))
                  (setf (svref storage i) next-result)
                  (unless next-result
                    (setf continuation nil))
                  (while next-result)
                  (finally (setf counter i)
                           (return next-result))))))))

(defun make-parse-result (continuation)
  (make-instance 'parse-result :store
                 (make-instance 'parse-result-store :continuation continuation)))

(defun current-result (parse-result)
  (when (= (current-of parse-result) -1)
    (next-result parse-result))
  (nth-result (current-of parse-result) (store-of parse-result)))

(defun next-result (parse-result)
  (incf (current-of parse-result))
  (current-result parse-result))

(defun gather-results (parse-result)
  (let ((current-result (current-result parse-result))
        (continuation-results
         (iter (for result next (next-result parse-result))
               (while result)
               (collect result))))
    (when current-result
      (cons current-result continuation-results))))

(defun copy-parse-result (parse-result)
  (make-instance 'parse-result :store (store-of parse-result)))

;;; here parser spec is list of (pattern optional-guard comprehension)
;;; using do-like notation, <- is special

;;; list of either monads: (monad parameters), name bindings (<- name monad)
;;; simple, no let

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun do-notation (monad-sequence bind ignore-gensym)
    (destructuring-bind (monad . rest) monad-sequence
      (cond ((endp rest)
             monad)
            ((and (listp monad)
                  (eql (car monad) '<-))
             (destructuring-bind (<- name monad) monad
               (declare (ignore <-))
               `(,bind ,monad
                       #'(lambda (,name)
                           ,(do-notation rest bind ignore-gensym)))))
            (t
             `(,bind ,monad
                     #'(lambda (,ignore-gensym)
                         (declare (ignore ,ignore-gensym))
                         ,(do-notation rest bind ignore-gensym))))))))

(defmacro mdo (&body spec)
  "Combinator: use do-like notation to sequentially link parsers. (<- name parser) allows capturing of return values."
  (with-unique-names (ignore-gensym)
    (do-notation spec 'bind ignore-gensym)))

(defparameter *curtail-table* (make-hash-table))
(defparameter *memo-table* (make-hash-table))

(defun parse-string (parser string)
  "Parse a string, return a PARSE-RESULT object. All returned values may share structure."
  (let ((*memo-table* (make-hash-table))
        (*curtail-table* (make-hash-table))
        (context (make-context string)))
    (values (make-parse-result (funcall parser context))
            (front-of context))))

(defun parse-string* (parser string &key (complete nil))
  "Parse a string and return the first result, whether the parse was incomplete, whether it was
successfull, and the context front as multiple values. The context front is an object containg the
context latest in the input and a list of lists of parser tags which were current at that point,
which allows approximate error reporting. It will be nil if the parse is successful and complete.

 If COMPLETE is T, return the first parse to consume the input
completely. If COMPLETE is :FIRST return the first result only when it the whole input was consumed,
or immediately return nil."
  (multiple-value-bind (parse-result front) (parse-string (ensure-parser parser) string)
    (ecase complete
      ((nil :first)
         (let ((result
                (current-result parse-result)))
           (cond ((or (null result)
                      (and (eql complete :first)
                           (not (end-context-p (suffix-of result)))))
                  (values nil nil nil front))
                 ((not (end-context-p (suffix-of result)))
                  (values (tree-of result) (suffix-of result) t front))
                 (t (values (tree-of result) nil t nil)))))
      (t (iter (with results = parse-result)
               (for result = (next-result results))
               (while result)
               (when (end-context-p (suffix-of result))
                 (return (values (tree-of result) nil t nil)))
               (finally (return (values nil nil nil front))))))))
