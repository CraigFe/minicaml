open Types
open Typecheck
open Util

(** Insert a key-value pair in a dictionary *)
let insert_dict act_params =
  let (k, v, d) = (match act_params with
    | [k; v; d] -> (k, v, unpack_dict d)
    | _ -> raise WrongBindList) in
  EvtDict (isvalidkey (k, v) :: d)

(** Remove a key-value pair from a dictionary *)
let delete_dict act_params  =
  let (key, ed) = (match act_params with
    | [key; d] -> (key, unpack_dict d)
    | _ -> raise WrongPrimitiveArgs) in
  if not (key_exist key ed) then raise (DictError "key not found") else
  EvtDict (delete_key key ed)

(** Check if a key-value pair is in a dictionary *)
let haskey act_params =
  let (key, ed) = (match act_params with
    | [key; d] -> (key, unpack_dict d)
    | _ -> raise WrongPrimitiveArgs) in
  EvtBool(key_exist key ed)

(** Check if a dict contains a key *)
let getkey act_params =
  let (key, ed) = (match act_params with
    | [key; d] -> (key, unpack_dict d)
    | _ -> raise WrongPrimitiveArgs) in
  if not (key_exist key ed) then raise (DictError "key not found") else
  get_key_val key ed


(** Check if a dict contains a key *)
let filterkeys act_params =
  let (kll, ed) = (match act_params with
    | [kl; d] -> (unpack_list kl, unpack_dict d)
    | _ -> raise WrongPrimitiveArgs) in
  EvtDict(filter_by_keys kll ed)

let table = [
  ("insert", insert_dict);
  ("delete", delete_dict);
  ("haskey", haskey);
  ("getkey", getkey);
  ("filterkeys", filterkeys)
]