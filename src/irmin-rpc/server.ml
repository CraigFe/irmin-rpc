open Server_intf
open Capnp_rpc_lwt
open Lwt.Infix
open Utils

let ( let+ ) x f = Lwt.map f x

let ( let+! ) x f = Lwt.map (Result.map f) x

let ( let* ) = Lwt.bind

module type S = S

module type MAKER = MAKER

module Log = ( val Logs.src_log (Logs.Src.create "irmin.rpc" ~doc:"Irmin RPC")
                 : Logs.LOG )

let todo _ = failwith "TODO: unimplemented RPC endpoint"

(* let error m =
 *   let err = Capnp_rpc.Exception.v ~ty:`Failed m in
 *   Error (`Capnp (`Exception err)) *)

let ignore_result_set r =
  ignore (r : (Irmin_api.rw, string, Raw.Reader.builder_array_t) Capnp.Array.t)

module type RESULTS = sig
  type t

  val init_pointer : Raw.Builder.pointer_t -> t
end

let with_initialised_results (type t) (module Results : RESULTS with type t = t)
    f =
  let response, results = Service.Response.create Results.init_pointer in
  Service.return_lwt (fun () -> f results >|= Result.map (fun () -> response))

(* let wrap_implementation (Results: ) *)

module Make : MAKER =
functor
  (St : Irmin.S)
  (Endpoint_codec : Codec.SERIALISABLE with type t = St.Private.Sync.endpoint)
  ->
  struct
    type repo = St.repo

    type store = St.t

    type commit = St.commit

    type hash = St.hash

    let unwrap = function
      | Ok x -> x
      | Error (`Msg m) -> failwith m
      | Error (`Commit_not_found h) ->
          Fmt.failwith "Commit not found: %a" (Irmin.Type.pp St.Hash.t) h

    let process_write_error =
      Lwt.map
        (Result.map_error
           ( Fmt.strf "%a" (Irmin.Type.pp St.write_error_t)
           >> Capnp_rpc.Exception.v ~ty:`Failed
           >> fun e -> `Capnp (`Exception e) ))

    module Sync = Irmin.Sync (St)
    module Codec = Codec.Make (St)

    module Commit = struct
      type t = Raw.Client.Commit.t cap

      let read repo t =
        let open Raw.Client.Commit.Read in
        let req = Capability.Request.create_no_args () in
        let* str =
          Capability.call_for_value_exn t method_id req >|= Results.value_get
        in
        Codec.Commit.decode repo str

      let local commit =
        let module Commit = Raw.Service.Commit in
        object
          inherit Commit.service

          method tree_impl _params release_param_caps =
            let open Commit.Tree in
            release_param_caps ();
            Logs.info (fun f -> f "Commit.tree");
            with_initialised_results
              (module Results)
              (fun results ->
                let tree = St.Commit.tree commit in
                let tree_builder = Raw.Builder.Tree.init_root () in
                let+ () = Codec.Tree.encode tree_builder St.Key.empty tree in
                let (_ : Raw.Builder.Tree.t) =
                  Results.tree_set_builder results tree_builder
                in
                Ok ())

          method parents_impl _params release_param_caps =
            let open Commit.Parents in
            release_param_caps ();
            Logs.info (fun f -> f "Commit.parents");
            with_initialised_results
              (module Results)
              (fun results ->
                let parents =
                  St.Commit.parents commit |> List.map Codec.Hash.encode
                in
                ignore_result_set (Results.hashes_set_list results parents);
                Lwt.return (Ok ()))

          method info_impl _params release_param_caps =
            let open Commit.Info in
            release_param_caps ();
            Logs.info (fun f -> f "Commit.info");
            with_initialised_results
              (module Results)
              (fun results ->
                let info_builder = Raw.Builder.Info.init_root () in
                let () =
                  Codec.Info.encode info_builder (St.Commit.info commit)
                in
                let (_ : Raw.Builder.Info.t) =
                  Results.info_set_builder results info_builder
                in
                Lwt.return (Ok ()))

          method hash_impl _params release_param_caps =
            let open Commit.Hash in
            release_param_caps ();
            Logs.info (fun f -> f "Commit.hash");
            with_initialised_results
              (module Results)
              (fun results ->
                let hash = St.Commit.hash commit |> Codec.Hash.encode in
                Results.hash_set results hash;
                Lwt.return (Ok ()))

          method read_impl _params release_param_caps =
            let open Commit.Read in
            release_param_caps ();
            Logs.info (fun f -> f "Commit.read");
            with_initialised_results
              (module Results)
              (fun results ->
                let b_value = Raw.Builder.Commit.Value.init_root () in
                let+ () = Codec.Commit.encode b_value commit in
                let (_ : Raw.Builder.Commit.Value.t) =
                  Results.value_set_builder results b_value
                in
                Ok ())
        end
        |> Commit.local
    end

    module Store = struct
      type t = Raw.Client.Store.t cap

      let local store =
        let module Store = Raw.Service.Store in
        object
          inherit Store.service

          method find_impl params release_param_caps =
            let open Store.Find in
            let key = Params.key_get params in
            release_param_caps ();
            Logs.info (fun f -> f "Store.find");
            with_initialised_results
              (module Results)
              (fun results ->
                let key = Codec.Key.decode key |> unwrap in
                let+ () =
                  St.find store key
                  >|= Option.iter
                        (Codec.Contents.encode >> Results.contents_set results)
                in
                Ok ())

          method find_tree_impl params release_param_caps =
            let open Store.FindTree in
            let key = Params.key_get params in
            release_param_caps ();
            Logs.info (fun f -> f "Store.find_tree");
            with_initialised_results
              (module Results)
              (fun results ->
                let key = Codec.Key.decode key |> unwrap in
                let+ () =
                  let b_tree = Raw.Builder.Tree.init_root () in
                  St.find_tree store key
                  >>= Option.iter_lwt (fun tree ->
                          let+ () =
                            Codec.Tree.encode b_tree St.Key.empty tree
                          in
                          let (_ : Raw.Builder.Tree.t) =
                            Results.tree_set_builder results b_tree
                          in
                          ())
                in
                Ok ())

          method set_impl params release_param_caps =
            let open Store.Set in
            let key = Params.key_get params
            and info = Params.info_get params
            and contents = Params.contents_get params in
            release_param_caps ();
            Logs.info (fun f -> f "Store.set");
            Service.return_lwt (fun () ->
                let key = key |> Codec.Key.decode |> unwrap
                and info = info |> Codec.Info.decode
                and contents = contents |> Codec.Contents.decode |> unwrap in
                let+! () =
                  St.set ~info:(fun () -> info) store key contents
                  |> process_write_error
                in
                Service.Response.create_empty ())

          method set_tree_impl params release_param_caps =
            let open Store.SetTree in
            let key = Params.key_get params
            and info = Params.info_get params
            and tree = Params.tree_get params in
            release_param_caps ();
            Logs.info (fun f -> f "Store.set_tree");
            Service.return_lwt (fun () ->
                let key = key |> Codec.Key.decode |> unwrap
                and info = info |> Codec.Info.decode
                and tree = tree |> Codec.Tree.decode |> St.Tree.of_concrete in
                let+! () =
                  St.set_tree ~info:(fun () -> info) store key tree
                  |> process_write_error
                in
                Service.Response.create_empty ())

          method remove_impl = todo

          method merge_into_impl = todo

          method sync_impl = todo
        end
        |> Store.local
    end

    module Repo = struct
      type t = Raw.Client.Repo.t cap

      let local repo =
        let module Repo = Raw.Service.Repo in
        object
          inherit Repo.service

          method master_impl _params release_param_caps =
            let open Repo.Master in
            release_param_caps ();
            Logs.info (fun f -> f "Repo.master");
            with_initialised_results
              (module Results)
              (fun results ->
                let+ store = St.master repo in
                Results.store_set results (Some (Store.local store));
                Ok ())

          method of_branch_impl params release_param_caps =
            let open Repo.OfBranch in
            let branch = Params.branch_get params in
            release_param_caps ();
            Log.info (fun f -> f "Repo.of_branch: %s" branch);
            with_initialised_results
              (module Results)
              (fun results ->
                let branch = branch |> Codec.Branch.decode |> unwrap in
                let+ store = St.of_branch repo branch in
                Results.store_set results (Some (Store.local store));
                Ok ())

          method branch_list_impl _params release_param_caps =
            let open Repo.BranchList in
            release_param_caps ();
            Log.info (fun f -> f "Repo.branch_list");
            with_initialised_results
              (module Results)
              (fun results ->
                let+ branches = St.Repo.branches repo in
                let branches = List.map Codec.Branch.encode branches in
                Results.branches_set_list results branches |> ignore_result_set;
                Ok ())

          method branch_remove_impl params release_param_caps =
            let open Repo.BranchRemove in
            let branch = Params.branch_get params in
            release_param_caps ();
            Log.info (fun f -> f "Repo.branch_remove: %s" branch);
            Service.return_lwt (fun () ->
                let branch = branch |> Codec.Branch.decode |> unwrap in
                let+ () = St.Branch.remove repo branch in
                Ok (Service.Response.create_empty ()))

          method branch_set_impl params release_param_caps =
            let open Repo.BranchSet in
            let branch = Params.branch_get params in
            let commit = Params.commit_get params |> Option.get in
            release_param_caps ();
            Service.return_lwt (fun () ->
                let branch = branch |> Codec.Branch.decode |> unwrap in
                let* commit = Commit.read repo commit >|= unwrap in
                let+ () = St.Branch.set repo branch commit in
                Ok (Service.Response.create_empty ()))

          method commit_of_hash_impl params release_param_caps =
            let open Repo.CommitOfHash in
            let hash = Params.hash_get params in
            release_param_caps ();
            Logs.info (fun f -> f "Repo.commit_of_hash: %s" hash);
            with_initialised_results
              (module Results)
              (fun results ->
                let hash = hash |> Codec.Hash.decode |> unwrap in
                let+ commit = St.Commit.of_hash repo hash in
                commit |> Option.map Commit.local |> Results.commit_set results;
                Ok ())
        end
        |> Repo.local
    end

    let local ctx =
      let module I = Raw.Service.Irmin in
      object
        inherit I.service

        method repo_impl _params release_param_caps =
          let open I.Repo in
          release_param_caps ();
          let response, results =
            Service.Response.create Results.init_pointer
          in
          Results.repo_set results (Some (Repo.local ctx));
          Service.return response

        method heartbeat_impl = todo
      end
      |> I.local
  end
