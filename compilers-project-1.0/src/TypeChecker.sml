(* A type-checker for Fasto. *)

structure TypeChecker = struct

(*

A type-checker checks that all operations in a (Fasto) program are performed on
operands of an appropriate type. Furthermore, a type-checker infers any types
missing in the original program text, necessary for well-defined machine code
generation.

The main function of interest in this module is:

  val checkProg : Fasto.UnknownTypes.Prog -> Fasto.KnownTypes.Prog

*)

open Fasto

(* An exception for reporting type errors. *)
exception Error of string * pos

structure In = Fasto.UnknownTypes
structure Out = Fasto.KnownTypes

type functionTable = (Type * Type list * pos) SymTab.SymTab
type variableTable = Type SymTab.SymTab


(* Table of predefined conversion functions *)
val initFunctionTable : functionTable =
    SymTab.fromList
        [( "chr", (Char, [Int], (0,0))),
         ( "ord", (Int, [Char], (0,0)))
        ]

(* Aliases to library functions *)
val zip = ListPair.zip
val unzip = ListPair.unzip
val map = List.map
val foldl = List.foldl
val foldr = List.foldr

(* Pretty-printer for function types, for error messages *)
fun showFunType ( [] ,res) = " () -> " ^ ppType res
  | showFunType (args,res) = String.concatWith " * " (map ppType args)
                               ^ " -> " ^ ppType res

(* Type comparison that returns the type, raising an exception upon mismatch *)
fun checkTypesEqualOrError pos (t1, t2) =
    if t1 = t2 then t1 else
    raise Error ("Cannot match types "^ppType t1^" and "^ppType t2, pos)

(* Determine if a value of some type can be printed with write() *)
fun printable (Int) = true
  | printable (Bool) = true
  | printable (Char) = true
  | printable (Array Char) = true
  | printable _ = false  (* For all other array types *)
                      

                                      
(* Type-check the two operands to a binary operator - they must both be of type 't' *)
fun checkBinOp ftab vtab (pos, t, e1, e2) =
    let val (t1, e1') = checkExp ftab vtab e1
        val (t2, e2') = checkExp ftab vtab e2
    in  if (t = t1 andalso t = t2)
        then (t, e1', e2')
        else raise Error ("In checkBinOp: types not equal "^ppType t^" and "^ppType t1^" and "^ppType t2, pos)
    end

(* Determine the type of an expression.  On the way, decorate each node in the
   syntax tree with inferred types.  An exception is raised immediately on the
   first type mismatch - this happens in "checkTypesEqualOrError".  (It could instead
   collect each error as part of the result of checkExp and report all errors
   at the end.) *)
and checkExp ftab vtab (exp : In.Exp)
  = case exp of
      In.Constant  (v, pos)     => (valueType v, Out.Constant (v, pos))
    | In.StringLit (s, pos)     => (Array Char, Out.StringLit (s, pos))
    | In.ArrayLit  ([], _, pos) => raise Error("Impossible empty array", pos)
    | In.ArrayLit  (exp::exps, _, pos) =>
      let val (type_exp, exp_dec)    = checkExp ftab vtab exp
          val (types_exps, exps_dec) = unzip (map (checkExp ftab vtab) exps)
          val same_type = foldl (checkTypesEqualOrError pos) type_exp types_exps
      (* join will raise an exception if types do not match *)
      in (Array same_type,
          Out.ArrayLit (exp_dec::exps_dec, same_type, pos))
      end

    | In.Var (s, pos)
      => (case SymTab.lookup s vtab of
              NONE   => raise Error (("Unknown variable " ^ s), pos)
            | SOME t => (t, Out.Var (s, pos)))

    | In.Plus (e1, e2, pos)
      => let val (_, e1_dec, e2_dec) = checkBinOp ftab vtab (pos, Int, e1, e2)
         in (Int,
             Out.Plus (e1_dec, e2_dec, pos))
         end

    | In.Minus (e1, e2, pos)
      => let val (_, e1_dec, e2_dec) = checkBinOp ftab vtab (pos, Int, e1, e2)
         in (Int,
             Out.Minus (e1_dec, e2_dec, pos))
         end

    | In.Times (e1, e2, pos)
      => let val (_, e1_dec, e2_dec) = checkBinOp ftab vtab (pos, Int, e1, e2)
         in (Int, Out.Times (e1_dec, e2_dec, pos)) end

    | In.Divide (e1, e2, pos)
      => let val (_, e1_dec, e2_dec) = checkBinOp ftab vtab (pos, Int, e1, e2)
         in (Int, Out.Divide (e1_dec, e2_dec, pos)) end

    | In.And (e1, e2, pos)
      => let val (_, e1_dec, e2_dec) = checkBinOp ftab vtab (pos, Bool, e1, e2)
         in (Bool, Out.And (e1_dec, e2_dec, pos)) end

    | In.Or (e1, e2, pos)
      => let val (_, e1_dec, e2_dec) = checkBinOp ftab vtab (pos, Bool, e1, e2)
         in (Bool, Out.Or (e1_dec, e2_dec, pos)) end

    | In.Not (e, pos)
      => let val (e_type, e_dec) = checkExp ftab vtab e in
           ((checkTypesEqualOrError pos (e_type, Bool)), Out.Not(e_dec, pos))
         end
    | In.Negate (e, pos)
      => let val (e_type, e_dec) = checkExp ftab vtab e in
           ((checkTypesEqualOrError pos (e_type, Int)), Out.Not(e_dec, pos))
         end
    (* The types for e1, e2 must be the same. The result is always a Bool. *)
    | In.Equal (e1, e2, pos)
      => let val (t1, e1') = checkExp ftab vtab e1
             val (t2, e2') = checkExp ftab vtab e2
         in case (t1 = t2, t1) of
                 (false, _) => raise Error ("Cannot compare "^ ppType t1 ^
                                            "and "^ppType t2^"for equality",
                                              pos)
               | (true, Array _) => raise Error ("Cannot compare arrays", pos)
               | _ => (Bool, Out.Equal (e1', e2', pos))
         end

    | In.Less (e1, e2, pos)
      => let val (t1, e1') = checkExp ftab vtab e1
             val (t2, e2') = checkExp ftab vtab e2
         in case (t1 = t2, t1) of
                 (false, _) => raise Error ("Cannot compare "^ ppType t1 ^
                                            "and "^ppType t2^"for equality",
                                            pos)
               | (true, Array _) => raise Error ("Cannot compare arrays", pos)
               | _ => (Bool,
                       Out.Less (e1', e2', pos))
         end

    | In.If (pred, e1, e2, pos)
      => let val (pred_t, pred') = checkExp ftab vtab pred
             val (t1, e1') = checkExp ftab vtab e1
             val (t2, e2') = checkExp ftab vtab e2
             val target_type = checkTypesEqualOrError pos (t1, t2)
         in case pred_t of
                Bool => (target_type,
                         Out.If (pred', e1', e2', pos))
              | otherwise => raise Error ("Non-boolean predicate", pos)
         end

    (* Look up f in function table, get a list of expected types for each
       function argument and an expected type for the return value. Check
       each actual argument.  Ensure that each actual argument type has the
       expected type. *)
    | In.Apply (f, args, pos)
      => let val (result_type, expected_arg_types, _) =
                 case SymTab.lookup f ftab of
                     SOME match => match  (* 2-tuple *)
                   | NONE       => raise Error ("Unknown function " ^ f, pos)
             val (arg_types, args_dec) = unzip (map (checkExp ftab vtab) args)
             val _ = map (checkTypesEqualOrError pos) (zip (arg_types, expected_arg_types))
          in (result_type, Out.Apply (f, args_dec, pos))
          end

    | In.Let (In.Dec (name, exp, pos1), exp_body, pos2)
      => let val (t1, exp_dec)      = checkExp ftab vtab exp
             val new_vtab           = SymTab.bind name t1 vtab
              val (t2, exp_body_dec) = checkExp ftab new_vtab exp_body
         in (t2,
             Out.Let (Out.Dec (name, exp_dec, pos1), exp_body_dec, pos2))
         end

    | In.Read (t, pos) => (t, Out.Read (t, pos))

    | In.Write (e, _, pos)
      => let val (t, e') = checkExp ftab vtab e
         in if printable t
            then (t, Out.Write (e', t, pos))
            else raise Error ("Cannot write type " ^ ppType t, pos)
         end

    | In.Index (s, i_exp, t, pos)
      => let val (e_type, i_exp_dec) = checkExp ftab vtab i_exp
             val arr_type =
                 case SymTab.lookup s vtab of
                     SOME (Array t) => t
                   | NONE => raise Error ("Unknown identifier " ^ s, pos)
                   | SOME other =>
                     raise Error (s ^ " has type " ^ ppType other ^
                                  ": not an array", pos)
         in (arr_type, Out.Index (s, i_exp_dec, arr_type, pos))
         end

    | In.Iota (n_exp, pos)
      => let val (e_type, n_exp_dec) = checkExp ftab vtab n_exp
         in if e_type = Int
            then (Array Int, Out.Iota (n_exp_dec, pos))
            else raise Error ("Iota: wrong argument type " ^ ppType e_type, pos)
         end
               
    | In.Map (f, arr_exp, _, _, pos)
      => let val (f_dec, ret_type, arg_type) = checkFunArg (f, vtab, ftab, pos)
             val (arr_type, arr_dec) = checkExp ftab vtab arr_exp
             (* checks that the array expression is an array and return type of elements*)
             val el_type = case arr_type of
                                Array t => t
                              | _ => raise Error ("Map argument is not an array"^ppType arr_type, pos)
         in (* checks if the elements in array and function input type is the same
               and that the function only takes one argument *)
           if hd(arg_type) = el_type andalso length(arg_type) = 1
           then (Array ret_type, Out.Map(f_dec, arr_dec, hd(arg_type), ret_type, pos))
           else raise Error ("Map: wrong argument type"
                             ^ ppType arr_type^"is not an array", pos)
         end
    | In.Reduce (f, n_exp, arr_exp, _, pos)
      => let val (f_dec, ret_type, arg_type) = checkFunArg (f, vtab, ftab, pos)
             val (arr_type, arr_dec) = checkExp ftab vtab arr_exp
             val (n_type, n_dec) = checkExp ftab vtab n_exp
             (* checks that the array expression is an array and return type of elements*)
             val el_type = case arr_type of
                                Array t => t
                              | _ => raise Error ("Reduce: wrong argument type"
                                                  ^ppType arr_type^ "is not an array", pos)
             (* Checks the type of the neutral element. *)
             val neutral_elem = if n_type = el_type
                                then n_type
                                else raise Error("Reduce: Wrong neutral element type"
                                                ^ppType n_type^ "is not matching", pos)
                                    
         in
           (* check function arguments and return-type aswell it only takes two arguments.*)
           if length(arg_type) =2 andalso (hd(arg_type)) = el_type
              andalso el_type = ret_type andalso List.nth(arg_type, 1) = el_type
           then (ret_type, Out.Reduce(f_dec, n_dec, arr_dec, ret_type, pos))
           else raise Error ("Reduce: wrong function argument type"
                             ^ ppType ret_type,pos)
         end

and checkFunArg (In.FunName fname, vtab, ftab, pos) =
    (case SymTab.lookup fname ftab of
         NONE             => raise Error ("Unknown identifier " ^ fname, pos)
       | SOME (ret_type, arg_types, _) => (Out.FunName fname, ret_type, arg_types))
  | checkFunArg (In.Lambda (rettype, params, body, funpos), vtab, ftab, pos) =
    let val lambda = In.FunDec ("<lambda>", rettype, params, body, funpos)
        val (Out.FunDec (_, _, _, body', _)) =
              checkFunWithVtable (lambda, vtab, ftab, pos)
    in (Out.Lambda (rettype, params, body', pos),
        rettype,
        map (fn (Param (_, ty)) => ty) params)
    end

(* Check a function declaration, but using a given vtable rather
than an empty one. *)
and checkFunWithVtable (In.FunDec (fname, rettype, params, body, funpos),
                        vtab, ftab, pos) =
    let (* Expand vtable by adding the parameters to vtab. *)
        fun addParam (Param (pname, ty), ptable) =
            case SymTab.lookup pname ptable of
                SOME _ => raise Error ("Multiple definitions of parameter name " ^ pname,
                                       funpos)
              | NONE   => SymTab.bind pname ty ptable
        val paramtable = foldl addParam (SymTab.empty()) params
        val vtab' = SymTab.combine paramtable vtab
        val (body_type, body') = checkExp ftab vtab' body
    in if body_type = rettype
       then (Out.FunDec (fname, rettype, params, body', pos))
       else raise Error ("Function declared to return type "
                         ^ ppType rettype
                         ^ " but body has type "
                         ^ ppType body_type, funpos)
    end

(* Convert a funDec into the (fname, ([arg types], result type),
   pos) entries that the function table, ftab, consists of, and
   update the function table with that entry. *)
fun updateFunctionTable (funDec, ftab) =
    let val In.FunDec (fname, ret_type, args, _, pos) = funDec
        val arg_types = map (fn (Param (_, ty)) => ty) args
    in case SymTab.lookup fname ftab of
           SOME (_, _, old_pos) => raise Error ("Duplicate function " ^ fname, pos)
        | NONE => SymTab.bind fname (ret_type, arg_types, pos) ftab
    end

(* Functions are guaranteed by syntax to have a known declared type.  This
   type is checked against the type of the function body, taking into
   account declared argument types and types of other functions called.
 *)
fun checkFun ftab (In.FunDec (fname, ret_type, args, body_exp, pos)) =
    checkFunWithVtable (In.FunDec (fname, ret_type, args, body_exp, pos),
                        SymTab.empty(), ftab, pos)

fun checkProg funDecs =
    let val ftab = foldr updateFunctionTable initFunctionTable funDecs
        val decorated_funDecs = map (checkFun ftab) funDecs
    in case SymTab.lookup "main" ftab of
           NONE         => raise Error ("No main function defined", (0,0))
         | SOME (_, [], _) => decorated_funDecs  (* all fine! *)
         | SOME (ret_type, args, mainpos) =>
           raise Error
             ("Unexpected argument to main: " ^ showFunType (args, ret_type) ^
              " (should be () -> <anything>)", mainpos)
    end
end
