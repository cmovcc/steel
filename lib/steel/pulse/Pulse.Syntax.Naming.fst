module Pulse.Syntax.Naming
module RTB = FStar.Reflection.Typing.Builtins
module RT = FStar.Reflection.Typing
module R = FStar.Reflection
open FStar.List.Tot
module E = Pulse.Elaborate.Pure
open Pulse.Syntax.Base
module U = Pulse.Syntax.Pure

let rec close_open_inverse' (t:term) 
                            (x:var { ~(x `Set.mem` freevars t) } )
                            (i:index)
  : Lemma (ensures close_term' (open_term' t (U.term_of_no_name_var x) i) x i == t)
          (decreases t)
  = match t with
    | Tm_Emp
    | Tm_VProp
    | Tm_Inames 
    | Tm_EmpInames
    | Tm_Unknown -> ()
    
    | Tm_Pure p ->
      close_open_inverse' p x i

    | Tm_Star l r ->
      close_open_inverse' l x i;
      close_open_inverse' r x i

    | Tm_ExistsSL _ t b _
    | Tm_ForallSL _ t b ->
      close_open_inverse' t x i;    
      close_open_inverse' b x (i + 1)

    | Tm_FStar t _ ->
      RT.close_open_inverse' i t x

let close_open_inverse_comp' (c:comp)
                             (x:var { ~(x `Set.mem` freevars_comp c) } )
                             (i:index)
  : Lemma (ensures close_comp' (open_comp' c (U.term_of_no_name_var x) i) x i == c)
  = match c with
    | C_Tot t ->
      close_open_inverse' t x i

    | C_ST s ->
      close_open_inverse' s.res x i;
      close_open_inverse' s.pre x i;      
      close_open_inverse' s.post x (i + 1)

    | C_STAtomic n s
    | C_STGhost n s ->    
      close_open_inverse' n x i;    
      close_open_inverse' s.res x i;
      close_open_inverse' s.pre x i;      
      close_open_inverse' s.post x (i + 1)

let close_open_inverse_opt' (t:option term)
                            (x:var { ~(x `Set.mem` freevars_opt t) })
                            (i:index)
  : Lemma (ensures close_term_opt' (open_term_opt' t (U.term_of_no_name_var x) i) x i == t)
  = match t with
    | None -> ()
    | Some t -> close_open_inverse' t x i


let rec close_open_inverse_list' (t:list term)
                                 (x:var { ~(x `Set.mem` freevars_list t) })
                                 (i:index)
  : Lemma (ensures close_term_list' (open_term_list' t (U.term_of_no_name_var x) i) x i == t)
  = match t with
    | [] -> ()
    | hd::tl ->
      close_open_inverse' hd x i;
      close_open_inverse_list' tl x i


let rec close_open_inverse_st'  (t:st_term) 
                                (x:var { ~(x `Set.mem` freevars_st t) } )
                                (i:index)
  : Lemma (ensures close_st_term' (open_st_term' t (U.term_of_no_name_var x) i) x i == t)
          (decreases t)
  = match t.term with
    | Tm_Return { term = t } ->
      close_open_inverse' t x i

    | Tm_ElimExists { p } ->
      close_open_inverse' p x i    

    | Tm_Abs { b; pre; body; ret_ty; post } ->
      close_open_inverse' b.binder_ty x i;
      close_open_inverse_st' body x (i + 1);
      close_open_inverse_opt' pre x (i + 1);
      close_open_inverse_opt' ret_ty x (i + 1);      
      close_open_inverse_opt' post x (i + 2)

    | Tm_Bind { binder; head; body } ->
      close_open_inverse' binder.binder_ty x i;
      close_open_inverse_st' head x i;
      close_open_inverse_st' body x (i + 1)

    | Tm_TotBind { head; body } ->
      close_open_inverse' head x i;
      close_open_inverse_st' body x (i + 1)

    | Tm_STApp { head; arg } ->
      close_open_inverse' head x i;
      close_open_inverse' arg x i
    
    | Tm_IntroExists { p; witnesses } ->
      close_open_inverse' p x i;
      close_open_inverse_list' witnesses x i
    
    | Tm_ElimExists { p } ->
      close_open_inverse' p x i
      
    | Tm_While { invariant; condition; body } ->
      close_open_inverse' invariant x (i + 1);
      close_open_inverse_st' condition x i;
      close_open_inverse_st' body x i

    | Tm_If { b; then_; else_; post } ->
      close_open_inverse' b x i;    
      close_open_inverse_st' then_ x i;    
      close_open_inverse_st' else_ x i;
      close_open_inverse_opt' post x (i + 1)

    | Tm_Par { pre1; body1; post1; pre2; body2; post2 } ->
      close_open_inverse' pre1 x i;
      close_open_inverse_st' body1 x i;
      close_open_inverse' post1 x (i + 1);
      close_open_inverse' pre2 x i;
      close_open_inverse_st' body2 x i;
      close_open_inverse' post2 x (i + 1)

    | Tm_WithLocal { initializer; body } ->
      close_open_inverse' initializer x i;
      close_open_inverse_st' body x (i + 1)

    | Tm_Rewrite { t1; t2 } ->
      close_open_inverse' t1 x i;
      close_open_inverse' t2 x i

    | Tm_Admit { typ; post } ->
      close_open_inverse' typ x i;
      close_open_inverse_opt' post x (i + 1)

    | Tm_Protect { t } ->
      close_open_inverse_st' t x i
      
let close_open_inverse (t:term) (x:var { ~(x `Set.mem` freevars t) } )
  : Lemma (ensures close_term (open_term t x) x == t)
          (decreases t)
  = close_open_inverse' t x 0

let close_open_inverse_st (t:st_term) (x:var { ~(x `Set.mem` freevars_st t) } )
  : Lemma (ensures close_st_term (open_st_term t x) x == t)
          (decreases t)
  = close_open_inverse_st' t x 0

let rec open_with_gt_ln (e:term) (i:int) (t:term) (j:nat)
  : Lemma
      (requires ln' e i /\ i < j)
      (ensures open_term' e t j == e)
      (decreases e) =
  match e with
  | Tm_Emp
  | Tm_VProp
  | Tm_Inames
  | Tm_EmpInames
  | Tm_Unknown -> ()
  | Tm_Pure p -> open_with_gt_ln p i t j
  | Tm_Star e1 e2 ->
    open_with_gt_ln e1 i t j;
    open_with_gt_ln e2 i t j
  | Tm_ExistsSL _ t1 body _
  | Tm_ForallSL _ t1 body ->
    open_with_gt_ln t1 i t j;
    open_with_gt_ln body (i + 1) t (j + 1)
  | Tm_FStar _ _ -> admit()

let open_with_gt_ln_st (s:st_comp) (i:int) (t:term) (j:nat)
  : Lemma (requires ln_st_comp s i /\ i < j)
          (ensures open_st_comp' s t j == s) =
  let {res; pre; post} = s in
  open_with_gt_ln res i t j;
  open_with_gt_ln pre i t j;
  open_with_gt_ln post (i + 1) t (j + 1)

let open_with_gt_ln_comp (c:comp) (i:int) (t:term) (j:nat)
  : Lemma (requires ln_c' c i /\ i < j)
          (ensures open_comp' c t j == c) =
  match c with
  | C_Tot t1 -> open_with_gt_ln t1 i t j
  | C_ST s -> open_with_gt_ln_st s i t j
  | C_STAtomic inames s
  | C_STGhost inames s ->
    open_with_gt_ln inames i t j;
    open_with_gt_ln_st s i t j

let rec close_with_non_freevar (e:term) (x:var) (i:nat)
  : Lemma
      (requires ~ (x `Set.mem` freevars e))
      (ensures close_term' e x i == e)
      (decreases e) =
  
  match e with
  | Tm_Emp
  | Tm_VProp
  | Tm_Inames
  | Tm_EmpInames
  | Tm_Unknown -> ()
  | Tm_Star t1 t2 ->
    close_with_non_freevar t1 x i;
    close_with_non_freevar t2 x i
  | Tm_Pure p -> close_with_non_freevar p x i
  | Tm_ExistsSL _ t1 body _
  | Tm_ForallSL _ t1 body ->
    close_with_non_freevar t1 x i;
    close_with_non_freevar body x (i + 1)
  | Tm_FStar _ _ -> admit()

let close_with_non_freevar_st (s:st_comp) (x:var) (i:nat)
  : Lemma
    (requires ~ (x `Set.mem` freevars_st_comp s))
    (ensures close_st_comp' s x i == s) =
  let {res; pre; post} = s in
  close_with_non_freevar res x i;
  close_with_non_freevar pre x i;
  close_with_non_freevar post x (i + 1)

let close_comp_with_non_free_var (c:comp) (x:var) (i:nat)
  : Lemma
    (requires ~ (x `Set.mem` freevars_comp c))
    (ensures close_comp' c x i == c) =
  match c with
  | C_Tot t1 -> close_with_non_freevar t1 x i
  | C_ST s -> close_with_non_freevar_st s x i
  | C_STAtomic inames s
  | C_STGhost inames s ->
    close_with_non_freevar inames x i;
    close_with_non_freevar_st s x i
