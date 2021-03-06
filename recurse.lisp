(in-package :parser-combinators)

(defun curtail? (parser &optional (label (gensym)))
  "Add recursion curtailing to promise."
  (unless (gethash label *curtail-table*)
    (setf (gethash label *curtail-table*) (make-hash-table)))
  (let ((curtail-table (gethash label *curtail-table*)))
    (labels ((curtailed (inp)
               (multiple-value-bind (counter counter-p) (gethash (position-of inp) curtail-table)
                 (cond (counter-p
                        (destructuring-bind (c . l) counter
                          (cond ((>= c (1+ l))
                                 (funcall (zero) inp))
                                (t
                                 (incf (car counter))
                                 (funcall parser inp)))))
                       (t
                        (setf (gethash (position-of inp) curtail-table)
                              (cons 1 (- (length-of inp) (position-of inp))))
                        (funcall parser inp))))))
      #'curtailed)))
