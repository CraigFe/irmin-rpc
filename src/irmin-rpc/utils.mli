val ( >> ) : ('a -> 'b) -> ('b -> 'c) -> 'a -> 'c
(** Left-to-right function composition. *)

module Option : sig
  include module type of Option

  val iter_lwt : ('a -> unit Lwt.t) -> 'a option -> unit Lwt.t
end