(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining a   *)
(* copy of this software and associated documentation files (the "Software"),*)
(* to deal in the Software without restriction, including without limitation *)
(* the rights to use, copy, modify, merge, publish, distribute, sublicense,  *)
(* and/or sell copies of the Software, and to permit persons to whom the     *)
(* Software is furnished to do so, subject to the following conditions:      *)
(*                                                                           *)
(* The above copyright notice and this permission notice shall be included   *)
(* in all copies or substantial portions of the Software.                    *)
(*                                                                           *)
(* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR*)
(* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  *)
(* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL   *)
(* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER*)
(* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING   *)
(* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER       *)
(* DEALINGS IN THE SOFTWARE.                                                 *)
(*                                                                           *)
(*****************************************************************************)

(** The [S] signature is similar to {!Seq.S} except that suspended nodes are
    wrapped in a result.

    This allows some additional traversors ([map_e], etc.) to be applied lazily.

    The functions [of_seq] and [of_seq_e] allow conversion from vanilla
    sequences. *)
module type S = sig
  (** This is similar to {!Stdlib.Seq.S}[.t] but the suspended node is a result.

      Consequently, the sequence of elements may be interrupted by an error.
      Specifically, there are two possible kinds of sequences:

      - {e interrupted sequences} where one of the suspended nodes is not
        returned and an [Error _] is produced instead, and
      - {e whole sequences} where all the suspended nodes are actually returned
        inside an [Ok _].

      All the traversors below treat sequence interruption as an error that is
      returned as is.

      Also note that nodes are suspended by a continuation rather than a lazy
      block. As a result, different traversals of the same sequence can lead to
      repeated evaluations of the same elements, or distinct sets of elements,
      or even a different kind of sequence. E.g., if a suspended sequence fails
      or succeeds depending on the content of a reference.

      This is not recommended. You should use deterministic sequences that do
      not depend on state. Or you should use one-shot sequences that are used
      once and then never again. The documentation of this module is written
      assuming you adhere to these constraints. *)
  type ('a, 'e) t = unit -> (('a, 'e) node, 'e) result

  and (+'a, 'e) node = Nil | Cons of 'a * ('a, 'e) t

  (** A whole sequence of zero elements. *)
  val empty : ('a, 'e) t

  val return : 'a -> ('a, 'e) t

  val return_e : ('a, 'e) result -> ('a, 'e) t

  val interrupted : 'e -> ('a, 'e) t

  val nil : ('a, 'e) node

  (** [fold_left f init seq] is

      - if [seq] is a whole sequence, then [Ok x] where [x] is the result of
        folding [f] over all the elements of [seq] starting with [init], or
      - if [seq] is interrupted by [Error e], then [Error e].

      Note that, as with all other traversors below, if the sequence is
      interrupted, all the side-effects of [f] on the successful prefix of
      [seq] have already been applied before the traversal returns [Error _]. *)
  val fold_left : ('a -> 'b -> 'a) -> 'a -> ('b, 'e) t -> ('a, 'e) result

  (** [fold_left_e f init seq] folds [f] over the elements of [seq] with an
      accumulator set at [init]. It stops traversal (returning [Error _]) if [f]
      returns an [Error _] or if the sequence is interrupted. Otherwise it
      returns [Ok _].

      It is the responsibility of the caller to differentiate
      between errors from the function and errors from the sequence. The
      function {!map_error} may come in handy. E.g.,

{[
fold_left_e
  (fun acc item ->
    f acc item |> Result.map_error (fun e -> `Traverse e))
  init
  (s |> map_error (fun e -> `Interrupt e))
]}
*)
  val fold_left_e :
    ('a -> 'b -> ('a, 'e) result) -> 'a -> ('b, 'e) t -> ('a, 'e) result

  (** [fold_left_s f init seq] is a promise that resolves to

      - if [seq] is a whole sequence, then [Ok x] where [x] is the result of
        folding [f] over all the elements of [seq] starting with [init], or
      - if [seq] is interrupted by [Error e], then [Error e].

      Note that if it returns [Error _], the side-effects of [f] on previous
      elements have already been applied anyway.

      The elements are traversed sequentially. Specifically, a node's suspension
      is called only when the [f]-promise of the previous node has resolved.
      Thus, there might be yielding in between suspensions being called. *)
  val fold_left_s :
    ('a -> 'b -> 'a Lwt.t) -> 'a -> ('b, 'e) t -> ('a, 'e) result Lwt.t

  (** [fold_left_es f init seq] is a promise that resolves to

      - if [seq] is a whole sequence and [f]-promises always resolve
        successfully, then the result of folding [f] over all the elements of
        [seq] starting with [init],
      - otherwise, [Error _] with the error that interrupts the sequence or with
        an error returned by [f], whichever happens first.

      The elements are traversed sequentially. Specifically, a node's suspension
      is called only when the [f]-promise of the previous node has resolved.
      Thus, there might be yielding in between suspensions being called.

      See {!fold_left_e} for a warning about traversal and interruption errors
      being indistinguishable. *)
  val fold_left_es :
    ('a -> 'b -> ('a, 'e) result Lwt.t) ->
    'a ->
    ('b, 'e) t ->
    ('a, 'e) result Lwt.t

  (** [iter f seq] is [fold_left (fun () x -> f x) () seq] *)
  val iter : ('a -> unit) -> ('a, 'e) t -> (unit, 'e) result

  (** [iter_e f seq] is [fold_left_e (fun () x -> f x) () seq] *)
  val iter_e : ('a -> (unit, 'e) result) -> ('a, 'e) t -> (unit, 'e) result

  (** [iter_s f seq] is [fold_left_s (fun () x -> f x) () seq] *)
  val iter_s : ('a -> unit Lwt.t) -> ('a, 'e) t -> (unit, 'e) result Lwt.t

  (** [iter_es f seq] is [fold_left_es (fun () x -> f x) () seq] *)
  val iter_es :
    ('a -> (unit, 'e) result Lwt.t) -> ('a, 'e) t -> (unit, 'e) result Lwt.t

  (** [iter_p f seq] is a promise [p].

      - If [seq] is a whole sequence, then [p] resolves to [Ok ()] once all the
        promises created by [f] on the elements of [seq] have resolved.
      - If [seq] is interrupted by [Error e], then [p] resolves to [Error e]
        once all the promises created by [f] on the elements of the successful
        prefix of [seq] have resolved.

      Note that the behaviour for interrupted sequences is in line with the
      best-effort semantic of Lwtreslib. *)
  val iter_p : ('a -> unit Lwt.t) -> ('a, 'e) t -> (unit, 'e) result Lwt.t

  (** There is no [iter_ep] in [Bare]. The reason is that there can be two
      sources of failures and there is no satisfying way to combine failures for
      the caller. *)

  (** [map f seq] is a sequence [feq].

      - If [seq] is a whole sequence, then [feq] is a whole sequence where the
        elements are the result of the application of [f] on the elements of
        [seq].
      - If [seq] is an interrupted sequence, then [feq] is a sequence
        interrupted by [Error e] where the elements of the successful prefix are
        the result of the application of [f] on the elements of the successful
        prefix of [seq].
   *)
  val map : ('a -> 'b) -> ('a, 'e) t -> ('b, 'e) t

  (** [map_error f seq] is a sequence [feq].

      - If [seq] is a whole sequence, then [feq] is the same whole sequence.
      - If [seq] is an interrupted sequence, then [feq] is a sequence
        interrupted by [Error (f e)] where the elements of the successful prefix
        are the elements of the successful prefix of [seq]. *)
  val map_error : ('e -> 'f) -> ('a, 'e) t -> ('a, 'f) t

  (** [map_e f seq] is a sequence [feq].

      - If [seq] is a whole sequence and if [f] is successful on all the
        elements of [seq], then [feq] is a whole sequence where the elements are
        [x] where [Ok x] is the result of the application of [f] on the elements
        of [seq].
      - Otherwise [feq] is a sequence composed of elements of [seq] mapped by
        [f] and interrupted by [f] returning [Error] or by [seq]'s interruption
        (whichever comes first). *)
  val map_e : ('a -> ('b, 'e) result) -> ('a, 'e) t -> ('b, 'e) t

  (** [filter f s] is a sequence of the same kind as [s] with only the elements
      for which [f] returns [true]. *)
  val filter : ('a -> bool) -> ('a, 'e) t -> ('a, 'e) t

  (** [filter_e f s] is a sequence that is interrupted like [s] or by [f] being
      unsuccessful (whichever comes first) or whole (if neither cases apply).
      Whichever is the case, the elements of the resulting sequence are the
      elements of [s] for which [f] returns [Ok true]. *)
  val filter_e : ('a -> (bool, 'e) result) -> ('a, 'e) t -> ('a, 'e) t

  (** [filter_map f s] is a sequence of the same kind as [s] where the elements
      are transformed by [f] (when it returns [Some _]) or dropped (when it
      returns [None]). *)
  val filter_map : ('a -> 'b option) -> ('a, 'e) t -> ('b, 'e) t

  (** [filter_map_e f s] is a sequence that is whole or that is interrupted in
      the same way as [s] (if it is) or that is interrupted by [f] (if it
      happens). Whichever the case, the elements of the sequence or the
      successful prefix thereof are transformed by [f] (when it returns
      [Some _]) or dropped (when it returns [None]). *)
  val filter_map_e : ('a -> ('b option, 'e) result) -> ('a, 'e) t -> ('b, 'e) t

  (** [find f s] is

      - [Ok (Some x)] if [x] is the first element of [s] or the successful
        prefix of [s] for which [f x] holds, or
      - [Ok None] if [s] is whole and [f] doesn't hold for any of the elements
        of [s], or
      - [Error e] if [s] is interrupted by [e]. *)
  val find : ('a -> bool) -> ('a, 'e) t -> ('a option, 'e) result

  (** [find_e f s] is

      - [Ok (Some x)] if [x] is the first element of [s] or the successful
        prefix of [s] for which [f x] holds, or
      - [Ok None] if [s] is whole and [f] doesn't hold for any of the elements
        of [s], or
      - [Error e] if there is an element of [s] or the successful prefix of [s]
        for which [f] returns [Error e], or
      - [Error e] if [s] is interrupted by [e]. *)
  val find_e :
    ('a -> (bool, 'e) result) -> ('a, 'e) t -> ('a option, 'e) result

  (** [find_s] is similar to [find] but it returns a promise. Also note that the
      elements are traversed sequentially and that the sequence's node are
      unsuspended only when the previous node's predicate has been evaluated. *)
  val find_s : ('a -> bool Lwt.t) -> ('a, 'e) t -> ('a option, 'e) result Lwt.t

  (** [find_es] is similar to [find_e] but it returns a promise. Also note that
      the elements are traversed sequentially and that the sequence's node are
      unsuspended only when the previous node's predicate has been evaluated. *)
  val find_es :
    ('a -> (bool, 'e) result Lwt.t) ->
    ('a, 'e) t ->
    ('a option, 'e) result Lwt.t

  val of_seq : 'a Stdlib.Seq.t -> ('a, 'e) t

  val of_seq_e : ('a, 'e) result Stdlib.Seq.t -> ('a, 'e) t
end

(* Developer notes:

   We could use [Either.t] to distinguish between interruption and traversal
   failure. [Either] is introduced only in more recent versions of OCaml that we
   use here. We'll update to use [Either.t] later. *)
