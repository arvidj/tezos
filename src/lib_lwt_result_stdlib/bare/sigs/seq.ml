(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020 Nomadic Labs <contact@nomadic-labs.com>                *)
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

(** {1 Seq}

    A replacement for {!Stdlib.Seq} which
    - is exception-safe,
    - includes Lwt-, result- and Lwt-result-aware traversal functions.

    See {!Lwtreslib} for a general description of traversors and the meaning for
    the name suffixes. A full description is also below.

    All traversal functions that are suffixed with [_e] are within the result
    monad. Note that these functions have a "fail-early" behaviour: the
    traversal is interrupted as when any of the intermediate application fails
    (i.e., returns an [Error _]).

    All traversal functions that are suffixed with [_s] are within the Lwt
    monad. These functions traverse the elements sequentially: the promise for a
    given step of the traversal is only initiated when the promise for the
    previous step is resolved. Note that these functions have a fail-early
    behaviour: the traversal is interrupted if any of the intermediate promise
    is rejected.

    All the traversal functions that are suffixed with [_p] are within Lwt.
    These functions traverse the elements concurrently: the promise for all the
    steps are created immediately. The suffix [_p] is chosen for similarity with
    the {!Lwt_list} functions even though, as with {!Lwt_list}'s functions there
    is no parallelism involved, only concurrency. Note that these functions have
    a “best-effort” behaviour: the whole-traversal promise (i.e., the promise
    returned by the [_p]-suffixed function) only resolves once each of the step
    promises have resolved. Even if one of the step promise is rejected, the
    whole-traversal promise is only rejected once all the other step promises
    have resolved.

    All the traversal functions that are suffixed with [_es] are within the
    combined error-and-Lwt monad. These function traverse the elements
    sequentially with a fail-early behaviour for both rejection (as an Lwt
    promise) and failure (as a result).

    All the traversal functions that are suffixed with [_ep] are within the
    combined error-and-Lwt monad. These function traverse the elements
    concurrently with a best-effort behaviour.
*)

(** {2 Special consideration}

    Because of the type of {!Stdlib.Seq.t}, some interactions with Lwt are not
    possible. Specifically, note that the type includes the variant
    [unit -> 'a node] which is not within Lwt nor within the result monad.
    As a result, some of the traversals ([map_s], [map_e], etc.) cannot be
    applied lazily.

    Check-out the [S] variants ({!Seq_s.S}, {!Seq_e.S}, and
    {!Seq_es.S}) that integrate the base sequence type better with the monads'
    type. It is recommended that you use the variant as appropriate to your
    traversal. Note the presence of [of_seq] in each of those variants to
    convert from the standard [S.t]. *)

module type S = sig
  (** {3 Common interface with Stdlib} *)

  include
    module type of Stdlib.Seq
      with type 'a t = 'a Stdlib.Seq.t
       and type 'a node = 'a Stdlib.Seq.node

  (** {3 Lwtreslib-specific extensions} *)

  (** Similar to {!fold_left} but wraps the traversal in {!result}. The
      traversal is interrupted if one of the step returns an [Error _]. *)
  val fold_left_e :
    ('a -> 'b -> ('a, 'trace) result) -> 'a -> 'b t -> ('a, 'trace) result

  (** Similar to {!fold_left} but wraps the traversing in {!Lwt}. Each step of
      the traversal is started after the previous one has resolved. The
      traversal is interrupted if one of the promise is rejected. *)
  val fold_left_s : ('a -> 'b -> 'a Lwt.t) -> 'a -> 'b t -> 'a Lwt.t

  (** Similar to {!fold_left} but wraps the traversing in [result Lwt.t].
      Each step of the traversal is started after the previous one resolved. The
      traversal is interrupted if one of the step is rejected or is fulfilled
      with [Error _]. *)
  val fold_left_es :
    ('a -> 'b -> ('a, 'trace) result Lwt.t) ->
    'a ->
    'b t ->
    ('a, 'trace) result Lwt.t

  (** Similar to {!iter} but wraps the iteration in {!result}. The iteration
      is interrupted if one of the step returns an [Error _]. *)
  val iter_e : ('a -> (unit, 'trace) result) -> 'a t -> (unit, 'trace) result

  (** Similar to {!iter} but wraps the iteration in {!Lwt}. Each step
      of the iteration is started after the previous one resolved. The iteration
      is interrupted if one of the promise is rejected. *)
  val iter_s : ('a -> unit Lwt.t) -> 'a t -> unit Lwt.t

  (** Similar to {!iter} but wraps the iteration in [result Lwt.t]. Each step
      of the iteration is started after the previous one resolved. The iteration
      is interrupted if one of the promise is rejected of fulfilled with an
      [Error _]. *)
  val iter_es :
    ('a -> (unit, 'trace) result Lwt.t) -> 'a t -> (unit, 'trace) result Lwt.t

  (** Similar to {!iter} but wraps the iteration in [result Lwt.t]. All the
      steps of the iteration are started concurrently. The promise [iter_ep]
      resolves once all the promises of the traversal resolve. At this point it
      either:
      - is rejected if at least one of the promises is, otherwise
      - is fulfilled with [Error _] if at least one of the promises is,
        otherwise
      - is fulfilled with [Ok ()] if all the promises are. *)
  val iter_ep :
    ('a -> (unit, 'trace) result Lwt.t) ->
    'a t ->
    (unit, 'trace list) result Lwt.t

  (** Similar to {!iter} but wraps the iteration in {!Lwt}. All the
      steps of the iteration are started concurrently. The promise [iter_p f s]
      is resolved only once all the promises of the iteration are. At this point
      it is either fulfilled if all promises are, or rejected if at least one of
      them is. *)
  val iter_p : ('a -> unit Lwt.t) -> 'a t -> unit Lwt.t

  (** [find f t] is [Some x] where [x] is the first item in [t] such that
      [f x]. It is [None] if there are no such element. It does not terminate if
      the sequence is infinite and the predicate is always false. *)
  val find : ('a -> bool) -> 'a t -> 'a option

  (** [find_e f t] is similar to {!find} but wraps the search within
      [result]. Specifically, [find_e f t] is either
    - [Ok (Some x)] if forall [y] before [x] [f y = Ok false] and
      [f x = Ok true],
    - [Error e] if there exists [x] such that forall [y] before [x]
      [f y = Ok false] and [f x = Error e],
    - [Ok None] otherwise and [t] is finite,
    - an expression that never returns otherwise. *)
  val find_e :
    ('a -> (bool, 'trace) result) -> 'a t -> ('a option, 'trace) result

  (** [find_s f t] is similar to {!find} but wrapped within
      [Lwt.t]. The search is identical to [find_e] but each
      predicate is applied when the previous one has resolved. *)
  val find_s : ('a -> bool Lwt.t) -> 'a t -> 'a option Lwt.t

  (** [find_es f t] is similar to {!find} but wrapped within
      [result Lwt.t]. The search is identical to [find_e] but each
      predicate is applied when the previous one has resolved. *)
  val find_es :
    ('a -> (bool, 'trace) result Lwt.t) ->
    'a t ->
    ('a option, 'trace) result Lwt.t
end
