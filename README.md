irmin-rpc — CapNProto RPC server for Irmin
-------------------------------------------------------------------------------
%%VERSION%%

irmin-rpc is a Cap'N'Proto RPC server and client for Irmin. It allows for remote Irmin stores to be easily queried and modified.

irmin-rpc is distributed under the ISC license.

Homepage: https://github.com/zshipko/irmin-rpc

## Installation

irmin-rpc can be installed with `opam`:

    opam pin add irmin-rpc https://github.com/zshipko/irmin-rpc.git

After that, you will most likely want to install irmin-rpc-unix:

    opam pin add irmin-rpc-unix https://github.com/zshipko/irmin-rpc.git

If you don't use `opam` consult the [`opam`](opam) file for build
instructions.

## Example server

The example below will start a server on `127.0.0.1:9999` and run it until the process is killed. To run this example execute:

```shell
$ dune exec examples/server.exe
```

```ocaml
open Lwt.Infix

module Store = Irmin_mem.KV(Irmin.Contents.String)
module Rpc = Irmin_rpc_unix.Make(Store)

let main =
    Store.Repo.v (Irmin_mem.config ()) >>= fun repo ->
    Rpc.Server.create ~secret_key:`Ephemeral (`TCP ("127.0.0.1", 9999)) repo >>= fun server ->
    Printf.printf "Serving on: %s\n" (Uri.to_string (Rpc.Server.uri server));
    Rpc.Server.run server

let () = Lwt_main.run main
```

## Example client

This example shows how to connect to the server using the provided client. To run this example execute:

```shell
$ dune exec examples/client.exe
```

```ocaml
open Lwt.Infix

module Store = Irmin_mem.KV(Irmin.Contents.String)
module Rpc = Irmin_rpc_unix.Make(Store)

(* This was printed when running the server example above *)
let uri = "capnp://sha-256:YIhQi5oAx0XAUJc7XnbhbNooKDds0LV9zbtsepd3X6A@127.0.0.1:9999/WUNVqiE4hrUdV6GvTvnKq6yg-8xVvJmILcLlwPUVldo"

let main =
    Rpc.Client.connect (Uri.of_string uri) >>= fun client ->
    Rpc.Client.set client ["abc"] "123" >>= fun _ ->
    Rpc.Client.get client ["abc"] >|= function
    | Ok res -> assert (res = "123"); print_endline res
    | Error _ -> print_endline "Error encountered"

let () = Lwt_main.run main
```

## Documentation

The documentation and API reference is generated from the source
interfaces. It can be consulted [online][doc] or via `odig doc
irmin-rpc`.

[doc]: https://zshipko.github.io/irmin-rpc/doc

## Tests

In the distribution sample programs and tests are located in the
[`test`](test) directory. They can be built and run
with:

    dune runtest
