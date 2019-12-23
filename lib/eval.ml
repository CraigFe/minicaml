open Types
open Env
open Errors
open Util
open Typecheck

module T = ANSITerminal

(** Numerical Primitives *)

let int_binop (x, y) (op: int -> int -> int) = match (x, y) with
    | EvtInt(a), EvtInt(b) -> EvtInt(op a b)
    | _, _ -> raise (TypeError "type mismatch in arithmetical operation")

let bool_binop (x, y) (op: bool -> bool -> bool) = match (x, y) with
    | EvtBool(a), EvtBool(b) -> EvtBool(op a b)
    | _, _ -> raise (TypeError "type mismatch in boolean operation")

let bool_unop x (op: bool -> bool) = match x with
    | EvtBool(a) -> EvtBool(op a)
    | _ -> raise (TypeError "type mismatch in boolean operation")

let uniqueorfail l = if dup_key_exist l then
    raise (DictError "Duplicate key in dictionary")
    else l

(** Evaluate an expression in an environment *)
let rec eval (e: expr) (env: env_type) (n: stackframe) vb : evt =
    let n = push_stack n e in
    let depth = (match n with
        | StackValue(d, _, _) -> d
        | EmptyStack -> 0) in
    (* Partially apply eval to the current stackframe, verbosity and environment *)
    let ieval = fun x -> eval x env n vb in
    if vb then print_message ~color:T.Blue ~loc:(Nowhere)
        "Reduction at depth" "%d\nExpression:\n%s" depth (show_expr e)
    else ();
    let evaluated = (match e with
    | Unit -> EvtUnit
    | Integer n -> EvtInt n
    | Boolean b -> EvtBool b
    | String s -> EvtString s
    | Symbol x -> lookup env x ieval
    | List x -> EvtList (eval_list x ieval)
    | Tail l ->
        (match (ieval l) with
        | EvtList(ls) -> (match ls with
            | [] -> raise (ListError "empty list")
            | _::r -> EvtList r)
        | _ -> raise (ListError "not a list"))
    | Head l -> (match (ieval l) with
        | EvtList(ls) -> (match ls with
            | [] -> raise (ListError "empty list")
            | v::_ -> v )
        | _ -> raise (ListError "not a list"))
    | Cons(x, xs) -> (match (ieval xs) with
        | EvtList(ls) -> (match ls with
            | [] -> EvtList([(ieval x)])
            | lss -> EvtList((ieval x)::lss))
        | _ -> raise (ListError "not a list"))
    (* Dictionaries and operations *)
    | Dict(l) ->
        let el = uniqueorfail (List.map (fun (x,y) -> evalkv (x,y) ieval) l) in
        EvtDict el
    | DictInsert((k, v), d) ->
        let edl = (match ieval d with
            | EvtDict x -> x
            | _ -> failwith "Not a dictionary") in
        EvtDict (evalkv (k, v) ieval :: edl)
    | DictDelete(key, d) ->
        let edl = (match ieval d with
            | EvtDict x -> x
            | _ -> failwith "Not a dictionary") in
        let ek = ieval key in
        EvtDict (delete_key ek edl)
    | DictHaskey(key, d) ->
        let edl = (match ieval d with
            | EvtDict x -> x
            | _ -> failwith "Not a dictionary") in
        let ek = ieval key in
        EvtBool(key_exist ek edl)
    (* Catamorphisms and iterators *)
    | Mapv(f, s) ->
        let ef = ieval f in
        typecheck ef "fun";
        let es = ieval s in
        (match es with
            | EvtList x ->
                EvtList(List.map (fun x -> apply_with_evt ef x n vb) x)
            | EvtDict d ->
                let (keys, values) = unzip d in
                EvtDict(zip keys (List.map (fun x -> apply_with_evt ef x n vb) values))
            | _ -> failwith "Value is not iterable")

    | Fold(_, _) -> EvtUnit
    | Filter(_, _) -> EvtUnit
    | Sum   (x, y) ->   int_binop   (ieval x, ieval y)  (+)
    | Sub   (x, y) ->   int_binop   (ieval x, ieval y)  (-)
    | Mult  (x, y) ->   int_binop   (ieval x, ieval y)  ( * )
    | And   (x, y) ->   bool_binop  (ieval x, ieval y)  (&&)
    | Or    (x, y) ->   bool_binop  (ieval x, ieval y)  (||)
    | Not   x      ->   bool_unop   (ieval x)           (not)
    | Eq    (x, y) ->   EvtBool(compare_evt (ieval x) (ieval y) = 0)
    | Gt    (x, y) ->   EvtBool(compare_evt (ieval x) (ieval y) > 0)
    | Lt    (x, y) ->   EvtBool(compare_evt (ieval x) (ieval y) < 0)
    | IfThenElse (guard, first, alt) ->
        let g = ieval guard in
        typecheck g "bool";
        if g = EvtBool true then ieval first else ieval alt
    | Let (assignments, body) ->
        let evaluated_assignments = List.map
            (fun (_, value) -> AlreadyEvaluated (ieval value)) assignments
        and identifiers = fstl assignments in
        let new_env = bindlist env identifiers evaluated_assignments in
        eval body new_env n vb
    | Letlazy (assignments, body) ->
        let identifiers = fstl assignments in
        let new_env = bindlist env identifiers
            (List.map (fun (_, value) -> LazyExpression value) assignments) in
        eval body new_env n vb
    | Letrec (ident, value, body) ->
        (match value with
            | Lambda (form_params, fbody) ->
                let rec_env = (bind env ident
                    (AlreadyEvaluated (RecClosure(ident, form_params, fbody, env))))
                in eval body rec_env n vb
            | _ -> raise (TypeError "Cannot define recursion on non-functional values"))
    | Letreclazy (ident, value, body) ->
        (match value with
            | Lambda (_, _) ->
                let rec_env = (bind env ident (LazyExpression value))
                in eval body rec_env n vb
            | _ -> raise (TypeError "Cannot define recursion on non-functional values"))
    | Lambda (form_params,body) -> Closure(form_params, body, env)
    | Apply(f, act_params) ->
        let closure = ieval f in
        (match closure with
        | Closure(form_params, body, decenv) -> (* Use static scoping *)
            let evaluated_params = List.map (fun x -> AlreadyEvaluated (ieval x)) act_params in
            if (List.compare_lengths form_params act_params) > 0 then (* curry *)
                let p_length = List.length act_params in
                let applied_env = bindlist decenv (take p_length form_params) evaluated_params in
                Closure((drop p_length form_params), body, applied_env)
            else  (* apply the function *)
                let application_env = bindlist decenv form_params evaluated_params in
                eval body application_env n vb
        (* Apply a recursive function *)
        | RecClosure(name, form_params, body, decenv) ->
            let evaluated_params = List.map (fun x -> AlreadyEvaluated (ieval x)) act_params in
            if (List.compare_lengths form_params act_params) > 0 then (* curry *)
                let p_length = List.length act_params in
                let rec_env = (bind decenv name (AlreadyEvaluated closure)) in
                let applied_env = bindlist rec_env (take p_length form_params) evaluated_params in
                RecClosure(name, (drop p_length form_params), body, applied_env)
            else  (* apply the function *)
                let rec_env = (bind decenv name (AlreadyEvaluated closure)) in
                let application_env = bindlist rec_env form_params evaluated_params in
                eval body application_env n vb
        | _ -> raise (TypeError "Cannot apply a non functional value"))
    (* Eval a sequence of expressions but return the last *)
    | Sequence(exprl) ->
        let rec unroll el = (match el with
        | [] -> failwith "fatal: empty command sequence"
        | x::[] -> ieval x
        | x::xs -> (let _ = ieval x in unroll xs)) in unroll exprl
    (* Pipe two functions together, creating a new function
       That uses the first functions's result as the second's first argument *)
    | Pipe(e1, e2) ->
        (* Get the formal parameters of a function *)
        let getparams x = (match x with
            | Closure(params, _, _) -> params
            | RecClosure(_, params, _, _) -> params
            | _ -> failwith "fatal error") in
        (* Convert a list of identifiers to a list o symbols *)
        let syml l = List.map (fun x -> Symbol x) l in
        let f1 = ieval e1 and f2 = ieval e2 in
        typecheck f1 "fun"; typecheck f2 "fun";
        let params1 = getparams f1 in
        Closure(params1, Apply(e1, [Apply(e2, syml params1)]), env))
    in
    if vb then print_message ~color:T.Cyan ~loc:(Nowhere)
        "Evaluates to at depth" "%d\n%s\n" depth (show_evt evaluated)
    else ();
    evaluated;
and eval_list (l: list_pattern) ieval: evt list =
    match l with
        | EmptyList -> []
        | ListValue(x, xs) -> (ieval x)::(eval_list xs ieval)
(* Check if first elem of tuple is an allowed type and return tuple of evaluated values *)
and evalkv (x, y) ieval : (evt * evt) =
    let ex = ieval x in
        ((match ex with
        | EvtInt _ -> ex
        | EvtBool _ -> ex
        | EvtString _ -> ex
        | _ -> failwith "value not allowed as dictionary key"), ieval y)
(* Search for a value in an environment *)
and lookup (env: env_type) (ident: ide) ieval : evt =
    if ident = "" then failwith "invalid identifier" else
    match env with
    | [] -> raise (UnboundVariable ident)
    | (i, LazyExpression e) :: env_rest -> if ident = i then ieval e
        else lookup env_rest ident ieval
    | (i, AlreadyEvaluated e) :: env_rest -> if ident = i then e else
        lookup env_rest ident ieval
and apply_with_evt f p n vb =
    match f with
    | Closure(form_params, body, decenv) -> (* Use static scoping *)
        let evaluated_param =  AlreadyEvaluated p in
        if List.length form_params > 1 then (* curry *)
                let applied_env = bindlist decenv (take 1 form_params) [evaluated_param] in
                Closure((drop 1 form_params), body, applied_env)
            else  (* apply the function *)
                let application_env = bindlist decenv form_params [evaluated_param] in
                eval body application_env n vb
           (* Apply a recursive function *)
    | RecClosure(name, form_params, body, decenv) ->
        let evaluated_param =  AlreadyEvaluated p in
            if List.length form_params > 1 then (* curry *)
                let rec_env = (bind decenv name (AlreadyEvaluated f)) in
                let applied_env = bindlist rec_env (take 1 form_params) [evaluated_param] in
                RecClosure(name, (drop 1 form_params), body, applied_env)
            else  (* apply the function *)
                let rec_env = (bind decenv name (AlreadyEvaluated f)) in
                let application_env = bindlist rec_env form_params [evaluated_param] in
                eval body application_env n vb
    | _ -> raise (TypeError "Cannot apply a non functional value")
