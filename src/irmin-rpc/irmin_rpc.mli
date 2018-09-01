type t = [ `Irmin_b2b5cb4fd15c7d5a ] Capnp_rpc_lwt.Capability.t

module type CLIENT = sig
    module Store: Irmin.S
    val get: t -> ?branch:Store.branch -> Store.key -> (Store.contents, [`Msg of string]) result Lwt.t
    val get_tree: t -> ?branch:Store.branch -> Store.key -> Store.tree Lwt.t
    val set: t -> ?branch:Store.branch -> ?author:string -> ?message:string -> Store.key -> Store.contents -> Store.Commit.hash Lwt.t
    val set_tree: t -> ?branch:Store.branch -> ?author:string -> ?message:string -> Store.key -> Store.tree -> Store.Commit.hash Lwt.t
    val remove: t -> ?branch:Store.branch -> ?author:string -> ?message:string -> Store.key -> Store.Commit.hash Lwt.t
    val clone: t -> ?branch:Store.branch -> string -> Store.Commit.hash Lwt.t
    val pull: t -> ?branch:Store.branch -> ?author:string -> ?message:string -> string -> Store.Commit.hash Lwt.t
    val push: t -> ?branch:Store.branch -> string -> unit Lwt.t
    val merge: t -> ?branch:Store.branch -> ?author:string -> ?message:string -> Store.branch -> (Store.Commit.hash, Irmin.Merge.conflict) result Lwt.t
    val commit_info: t -> Store.Commit.Hash.t -> Irmin.Info.t Lwt.t
    val snapshot: ?branch:Store.branch -> t -> (Store.Commit.Hash.t, [`Msg of string]) result Lwt.t
    val revert: t -> ?branch:Store.branch -> Store.Commit.Hash.t -> bool Lwt.t
    val branches: t -> Store.branch list Lwt.t
end

module type S = sig
  module Store: Irmin.S

  val local: Store.repo -> t

  module Client: CLIENT with module Store = Store
end

module Make(Store: Irmin.S)(Info: sig
  val info: ?author:string -> ('a, Format.formatter, unit, Irmin.Info.f) format4 -> 'a
end): S with module Store = Store
