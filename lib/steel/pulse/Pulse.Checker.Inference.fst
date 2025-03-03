module Pulse.Checker.Inference

module L = FStar.List.Tot
module T = FStar.Tactics
open FStar.List.Tot
open Pulse.Syntax
open Pulse.Typing
open Pulse.Checker.Framing
module P = Pulse.Syntax.Printer

module RT = FStar.Reflection.Typing
module RUtil = Pulse.Reflection.Util

type uvar_id = nat

let embedded_uvar_lid = ["__pulse_embedded_uvar__"]

let is_uvar (t:term) : option uvar_id =
  match is_fvar t with
  | Some (l, [u]) ->
    if l = embedded_uvar_lid
    then begin match R.inspect_universe u with
               | R.Uv_BVar n -> Some n
               | _ -> None
         end
    else None
  | _ -> None


let wrap_nat_to_uvar (n:nat) : term =
  Tm_FStar 
    (R.pack_ln (R.Tv_UInst (R.pack_fv embedded_uvar_lid) [R.pack_universe (R.Uv_BVar n)]))
    FStar.Range.range_0

let gen_uvar () =
  let n = T.fresh () in
  assume (n >= 0);  // TODO: relying on the implementation of fresh in the typechecker
  n, wrap_nat_to_uvar n

let rec gen_uvars (t_head:term) : T.Tac (list uvar_id & comp) =
  let ropt = is_arrow t_head in
  match ropt with
  | Some (_, Some Implicit, c_rest) -> (
    let n, tm = gen_uvar () in
    let c_rest = open_comp_with c_rest tm in
    match c_rest with
    | C_ST c
    | C_STAtomic _ c
    | C_STGhost _ c ->
      [n], c_rest
    | C_Tot t ->
      let n_rest, comp_typ = gen_uvars t in
      n::n_rest, comp_typ
  )
  | _ ->
   T.fail (FStar.Printf.sprintf "gen_uvars: unexpected t_head: %s"
                                  (P.term_to_string t_head))

let rec check_valid_solution (n:uvar_id) (t:term) (uv_sols:list (uvar_id & term))
  : T.Tac (list (uvar_id & term)) =

  match uv_sols with
  | [] -> [n, t]
  | (n', t')::tl ->
    if n = n'
    then if eq_tm t t' then uv_sols
         else T.fail "check_valid_solution failed"
    else (n', t')::(check_valid_solution n t tl)

let uvar_index (t:term{Some? (is_uvar t)}) : uvar_id =
  Some?.v (is_uvar t)

let is_reveal_uvar (t:term) : option (universe & term & term) =
  match is_pure_app t with
  | Some (hd, None, arg) ->
    (match is_pure_app hd with
     | Some (hd, Some Implicit, ty) ->
       if Some? (is_uvar arg)
       then match is_fvar hd with
           | Some (l, [u]) ->
             if l = RUtil.reveal_lid
             then Some (u, ty, arg)
             else None
           | _ -> None
       else None
     | _ -> None)
  | _ -> None

let is_reveal (t:term) : bool =
  match leftmost_head t with
  | Some hd ->
    (match is_fvar hd with
     | Some (l, [_]) -> l = RUtil.reveal_lid
     | _ -> false)
  | _ -> false

let rec match_typ (t1 t2:term) (uv_sols:list (uvar_id & term))
  : T.Tac (list (uvar_id & term)) =

  match is_reveal_uvar t1, is_reveal t2 with
  | Some (u, ty, t), false ->
    check_valid_solution (uvar_index t) (mk_hide u ty t2) uv_sols
  | _ ->
    if Some? (is_uvar t1)
    then check_valid_solution (uvar_index t1) t2 uv_sols
    else if Some? (is_uvar t2)
    then T.fail "match_typ: t2 is a uvar"
    else match t1, t2 with
         | Tm_Pure t1, Tm_Pure t2 ->
           match_typ t1 t2 uv_sols
    
         | _, _ ->
           match is_pure_app t1, is_pure_app t2 with
           | Some (head1, arg_qual1, arg1), Some (head2, arg_qual2, arg2) ->
             if arg_qual1 = arg_qual2
             then let uv_sols = match_typ head1 head2 uv_sols in
                  match_typ arg1 arg2 uv_sols
             else uv_sols

           | _, _ -> uv_sols

let rec atomic_vprop_has_uvar (t:term) : bool =
  if Some? (is_uvar t) then true
  else match t with
       | Tm_Pure arg -> atomic_vprop_has_uvar arg
       | Tm_Emp -> false
       | _ ->
         match is_pure_app t with
         | Some (head, _, arg) ->
           assume (head << t /\ arg << t);
           atomic_vprop_has_uvar head || atomic_vprop_has_uvar arg
         | _ -> false

let rec atomic_vprops_may_match (t1:term) (t2:term) : bool =
  if Some? (is_reveal_uvar t1) && not (is_reveal t2)
  then true
  else if Some? (is_uvar t1) then true
  else match t1, t2 with
       | Tm_Pure x, Tm_Pure y ->
         atomic_vprops_may_match x y
       | _, _ ->
         match is_pure_app t1, is_pure_app t2 with
         | Some (head1, q1, arg1), Some (head2, q2, arg2) ->
           assume (head1 << t1 /\ arg1 << t1);
           assume (head2 << t2 /\ arg2 << t2);
           atomic_vprops_may_match head1 head2 &&
           q1 = q2 &&
           atomic_vprops_may_match arg1 arg2
         | _, _ -> eq_tm t1 t2

let infer_one_atomic_vprop (t:term) (ctxt:list term) (uv_sols:list (uvar_id & term))
  : T.Tac (list (uvar_id & term)) =

  if atomic_vprop_has_uvar t
  then
    let matching_ctxt = List.Tot.filter (fun ctxt_vp -> atomic_vprops_may_match t ctxt_vp) ctxt in
    // T.print (FStar.Printf.sprintf "infer_one_atomic_vprop %s, found %d matching candidates\n"
    //            (P.term_to_string t)
    //            (List.Tot.length matching_ctxt));
    if List.Tot.length matching_ctxt = 1
    then
      // let _ = T.print (FStar.Printf.sprintf "infer_one_atomic_vprop: matching %s and %s with %d exisiting solutions\n"
      //                    (P.term_to_string t)
      //                    (P.term_to_string (List.Tot.hd matching_ctxt))
      //                    (List.Tot.length uv_sols)) in 
      let uv_sols = match_typ t (List.Tot.hd matching_ctxt) uv_sols in
      T.print (FStar.Printf.sprintf "post matching, uv_sols has %d solutions\n"
                 (List.Tot.length uv_sols));
      uv_sols
    else uv_sols
  else uv_sols

let union_ranges (r0 r1:range) : T.Tac range = r0
let with_range (t:st_term') (r:range) : st_term = { term = t; range = r}

let rec rebuild_head (head:term) (uvs:list uvar_id) (uv_sols:list (uvar_id & term)) (r:range)
  : T.TacH st_term (requires fun _ -> List.Tot.length uvs > 0)
                   (ensures fun _ _ -> True) =
  let hd::tl = uvs in
  let ropt = List.Tot.find (fun (n1, _) -> hd = n1) uv_sols in
  match ropt with
  | None ->
    T.fail (FStar.Printf.sprintf
              "inference failed in building head, no solution for %d\n"
              hd)
  | Some (_, t2) ->
    match tl with
    | [] -> with_range (Tm_STApp { head; arg_qual= Some Implicit; arg=t2 })
                       r
    | _ ->
      let app_node = tm_pureapp head (Some Implicit) t2 in
      rebuild_head app_node tl uv_sols r

let try_inst_uvs_in_goal (ctxt:term)
                         (goal:vprop)
  : T.Tac (list (uvar_id & term))
  = let uv_sols = [] in
    let goal_list = vprop_as_list goal in
    let ctxt_list = vprop_as_list ctxt in
    let uv_sols =
      T.fold_left
        (fun uv_sols goal_vprop ->
          infer_one_atomic_vprop goal_vprop ctxt_list uv_sols)
        uv_sols
        goal_list
    in
    uv_sols

let print_solutions (l:list (uvar_id & term))
  : T.Tac string
  = String.concat "\n"
      (T.map #(uvar_id & term) #string
        (fun (u, t) ->
          Printf.sprintf "%d := %s" 
                       u
                       (P.term_to_string t))
        l)

let infer
  (head:term)
  (t_head:term)
  (ctxt_pre:term)
  (r:range)
  : T.Tac st_term =

  let uvs, pre =
    let uvs, comp = gen_uvars t_head in
    match comp with
    | C_ST st_comp
    | C_STAtomic _ st_comp
    | C_STGhost _ st_comp -> uvs, st_comp.pre
    | _ -> T.fail "infer:unexpected comp type"
  in

  if List.Tot.length uvs = 0
  then T.fail "Inference did not find anything to infer"
  else begin
    // T.print (FStar.Printf.sprintf "infer: generated %d uvars,\n\
    //                                ctx: {\n%s\n}\n\
    //                                st_comp.pre:{\n%s\n}"
    //            (List.Tot.length uvs)
    //            (P.term_list_to_string "\n" (vprop_as_list ctxt_pre))
    //            (P.term_list_to_string "\n" (vprop_as_list pre)));
    let uv_sols = try_inst_uvs_in_goal ctxt_pre pre in
    // T.print (Printf.sprintf "Got solutions: {\n%s\}"  (print_solutions uv_sols));
    let head = rebuild_head head uvs uv_sols r in
    // T.print (Printf.sprintf "Rebuilt head= %s" (P.st_term_to_string head));
    head
  end

let find_solution (sol:list (uvar_id * term)) (t:uvar_id)
  : option term
  = let r = List.Tot.find (fun (u, _) -> u = t) sol in
    match r with
    | None -> None
    | Some (_, t) -> Some t
    
let rec apply_solution (sol:list (uvar_id * term)) (t:term)
  : term
  = match t with
    | Tm_Emp
    | Tm_VProp
    | Tm_Inames
    | Tm_EmpInames
    | Tm_Unknown -> t

    | Tm_FStar _ _ ->
      if Some? (is_uvar t)
      then let n = uvar_index t in
            match find_solution sol n with
            | None -> t
            | Some t -> t
      else (match is_pure_app t with
            | Some (head, q, arg) ->
              assume (head << t);
              assume (arg << t);
              tm_pureapp (apply_solution sol head)
                         q
                         (apply_solution sol arg)
            | _ -> t)

    | Tm_Pure p ->
      Tm_Pure (apply_solution sol p)
    | Tm_Star l r ->
      Tm_Star (apply_solution sol l)
              (apply_solution sol r)
              
    | Tm_ExistsSL u t body se ->
      Tm_ExistsSL u (apply_solution sol t)
                    (apply_solution sol body)
                    se
       
    | Tm_ForallSL u t body ->
      Tm_ForallSL u (apply_solution sol t)
                    (apply_solution sol body)

let rec contains_uvar (t:term)
  : bool
  = match t with
    | Tm_Emp
    | Tm_VProp
    | Tm_Inames
    | Tm_EmpInames
    | Tm_Unknown -> false
      
    | Tm_Pure p ->
      (contains_uvar p)
      
    | Tm_Star l r ->
      (contains_uvar l) ||
      (contains_uvar r)
              
    | Tm_ExistsSL u t body se ->
      (contains_uvar t) ||
      (contains_uvar body)
       
    | Tm_ForallSL u t body ->
      (contains_uvar t) ||
      (contains_uvar body)
                    
    | Tm_FStar _ _ ->
      // TODO: should embedded F* terms be allowed to contain Pulse uvars?
      Some? (is_uvar t) ||
      (match is_pure_app t with
       | Some (head, _, arg) ->
         assume (head << t /\ arg << t);
         contains_uvar head || contains_uvar arg
       | _ -> false)

let try_unify (l r:term) = match_typ l r []
