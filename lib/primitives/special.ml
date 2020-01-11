open Types
open Typecheck
open Util

(* Special Primitives that are eval-recursive *)
(** Map a function over an iterable structure *)
let map args applyfun state =
  let f, s =
    match args with [ f; s ] -> (f, s) | _ -> iraise WrongPrimitiveArgs
  in
  stcheck (typeof f) TLambda;
  match s with
  | EvtList x ->
    EvtList
      (List.map (fun x -> applyfun f [ AlreadyEvaluated x ] state) x)
  | EvtDict d ->
    let keys, values = unzip d in
    EvtDict
      (zip keys
         (List.map
            (fun x -> applyfun f [ AlreadyEvaluated x ] state)
            values))
  | _ -> failwith "Value is not iterable"

let map2 args applyfun state =
  let f, s1, s2 =
    match args with
    | [ f; s1; s2 ] -> (f, s1, s2)
    | _ -> iraise WrongPrimitiveArgs
  in
  stcheck (typeof f) TLambda;
  match s1 with
  | EvtList x ->
    let y = unpack_list s2 in
    EvtList
      (List.map2
         (fun a b ->
            applyfun f [ AlreadyEvaluated a; AlreadyEvaluated b ] state)
         x y)
  | _ -> failwith "Value is not iterable"

let foldl args applyfun state =
  let f, a, s =
    match args with
    | [ f; ac; s ] -> (f, ac, s)
    | _ -> iraise WrongPrimitiveArgs
  in
  stcheck (typeof f) TLambda;
  match s with
  | EvtList x ->
    List.fold_left
      (fun acc x ->
         applyfun f [ AlreadyEvaluated acc; AlreadyEvaluated x ] state)
      a x
  | EvtDict d ->
    let _, values = unzip d in
    List.fold_left
      (fun acc x ->
         applyfun f [ AlreadyEvaluated acc; AlreadyEvaluated x ] state)
      a values
  | _ -> failwith "Value is not iterable"

let filter args applyfun state =
  let p, s =
    match args with
    | [ p; s ] -> (p, s)
    | _ -> iraise WrongPrimitiveArgs
  in
  stcheck (typeof p) TLambda;
  match s with
  | EvtList x ->
    EvtList
      (List.filter
         (fun x ->
            applyfun p [ AlreadyEvaluated x ] state = EvtBool true)
         x)
  | EvtDict d ->
    EvtDict
      (List.filter
         (fun (_, v) ->
            applyfun p [ AlreadyEvaluated v ] state = EvtBool true)
         d)
  | _ -> failwith "Value is not iterable"

let table = [
  ("map", (map, 2));
  ("map2", (map2, 3));
  ("foldl", (foldl, 3));
  ("filter", (filter, 2));
]