open Duniverse_lib

module Testable = struct
  include Testable
  open Duniverse

  module Repo = struct
    open Repo

    let unresolved = Alcotest.testable (pp Git.Ref.pp) (equal Git.Ref.equal)

    module Package = struct
      open Package

      let t = Alcotest.testable pp equal
    end
  end
end

module Flag = struct
  let compiler = OpamTypes.Pkgflag_Compiler
  let conf = OpamTypes.Pkgflag_Conf
end

let opam_factory ~name ~version =
  let name = OpamPackage.Name.of_string name in
  let version = OpamPackage.Version.of_string version in
  OpamPackage.create name version

let summary_factory ?(name = "undefined") ?(version = "1") ?dev_repo ?url_src
    ?(hashes = []) ?(depexts = []) ?(pinned = false) ?(flags = [])
    ?(has_build_commands = false) ?(has_install_commands = false) () =
  let package = opam_factory ~name ~version in
  {
    Opam.Package_summary.package;
    dev_repo;
    url_src;
    hashes;
    depexts;
    pinned;
    flags;
    has_build_commands;
    has_install_commands;
  }

let dependency_factory ?(vendored = true) ?name ?version ?dev_repo ?url_src
    ?hashes ?depexts ?flags ?has_build_commands ?has_install_commands () =
  let package_summary =
    summary_factory ?name ?version ?dev_repo ?url_src ?hashes ?depexts ?flags
      ?has_build_commands ?has_install_commands ()
  in
  { Opam.Dependency_entry.vendored; package_summary }

module Repo = struct
  module Package = struct
    let test_from_package_summary =
      let make_test ?(get_default_branch = fun _ -> assert false) ~name ~summary
          ~expected () =
        let test_name =
          Printf.sprintf "Repo.Package.from_package_summary: %s" name
        in
        let test_fun () =
          let actual =
            Duniverse.Repo.Package.from_package_summary ~get_default_branch
              summary
          in
          Alcotest.(
            check (result (option Testable.Repo.Package.t) Testable.r_msg))
            test_name expected actual
        in
        (test_name, `Quick, test_fun)
      in
      let simple_summary ?has_build_commands ?has_install_commands =
        summary_factory ~dev_repo:"d" ~url_src:(Other "u") ~name:"y"
          ~version:"v" ~hashes:[] ?has_build_commands ?has_install_commands
      in
      let simple_package =
        Ok
          (Some
             Duniverse.Repo.Package.
               {
                 opam = opam_factory ~name:"y" ~version:"v";
                 dev_repo = "d";
                 url = Other "u";
                 hashes = [];
                 pinned = false;
               })
      in
      [
        make_test ~name:"Base package"
          ~summary:(summary_factory ~name:"dune" ())
          ~expected:(Ok None) ();
        make_test ~name:"No url_src"
          ~summary:(summary_factory ?url_src:None ())
          ~expected:(Ok None) ();
        make_test ~name:"No dev_repo"
          ~summary:(summary_factory ?dev_repo:None ())
          ~expected:(Ok None) ();
        make_test ~name:"Regular"
          ~summary:(simple_summary ~has_build_commands:true ())
          ~expected:simple_package ();
        make_test ~name:"Has only install commands"
          ~summary:(simple_summary ~has_install_commands:true ())
          ~expected:simple_package ();
        make_test ~name:"Has both build & install commands"
          ~summary:
            (simple_summary ~has_build_commands:true ~has_install_commands:true
               ())
          ~expected:simple_package ();
        make_test
          ~name:"Has neither build nor install commands: virtual package"
          ~summary:
            (simple_summary ~has_build_commands:false
               ~has_install_commands:false ())
          ~expected:(Ok None) ();
        make_test ~name:"Uses default branch when no tag"
          ~get_default_branch:(function
            | "r" -> Ok "master" | _ -> assert false)
          ~summary:
            (summary_factory ~dev_repo:"d"
               ~url_src:(Git { repo = "r"; ref = None })
               ~name:"y" ~version:"v" ~hashes:[] ~has_build_commands:true ())
          ~expected:
            (Ok
               (Some
                  {
                    opam = opam_factory ~name:"y" ~version:"v";
                    dev_repo = "d";
                    url = Git { repo = "r"; ref = "master" };
                    hashes = [];
                    pinned = false;
                  }))
          ();
      ]
  end

  let package_factory ?(name = "") ?(version = "") ?(dev_repo = "")
      ?(url = Duniverse.Repo.Url.Other "") ?(hashes = []) ?(pinned = false) () =
    let open Duniverse.Repo.Package in
    let opam = opam_factory ~name ~version in
    { opam; dev_repo; url; hashes; pinned }

  let test_from_packages =
    let make_test ~name ~dev_repo ~packages ~expected () =
      let test_name = Printf.sprintf "Repo.from_packages: %s" name in
      let test_fun () =
        let dev_repo = Dev_repo.from_string dev_repo in
        let actual = Duniverse.Repo.from_packages ~dev_repo packages in
        Alcotest.(check (result Testable.Repo.unresolved Testable.r_msg))
          test_name expected actual
      in
      (test_name, `Quick, test_fun)
    in
    [
      make_test ~name:"Simple" ~dev_repo:"d"
        ~packages:
          [
            package_factory ~name:"p" ~version:"v" ~url:(Other "u") ~hashes:[]
              ();
          ]
        ~expected:
          (Ok
             {
               dir = "d";
               url = Other "u";
               hashes = [];
               provided_packages = [ opam_factory ~name:"p" ~version:"v" ];
             })
        ();
      make_test ~name:"Uses repository name as dir"
        ~dev_repo:"https://github.com/org/repo.git"
        ~packages:
          [
            package_factory ~name:"p" ~version:"v" ~url:(Other "u") ~hashes:[]
              ();
          ]
        ~expected:
          (Ok
             {
               dir = "repo";
               url = Other "u";
               hashes = [];
               provided_packages = [ opam_factory ~name:"p" ~version:"v" ];
             })
        ();
      make_test ~name:"Expection for dune"
        ~dev_repo:"https://github.com/ocaml/dune.git"
        ~packages:
          [
            package_factory ~name:"p" ~version:"v" ~url:(Other "u") ~hashes:[]
              ();
          ]
        ~expected:
          (Ok
             {
               dir = "dune_";
               url = Other "u";
               hashes = [];
               provided_packages = [ opam_factory ~name:"p" ~version:"v" ];
             })
        ();
      make_test ~name:"Add all to provided packages" ~dev_repo:"d"
        ~packages:
          [
            package_factory ~name:"d" ~version:"zdev" ~url:(Other "u")
              ~hashes:[] ();
            package_factory ~name:"d-lwt" ~version:"zdev" ~url:(Other "u")
              ~hashes:[] ();
          ]
        ~expected:
          (Ok
             {
               dir = "d";
               url = Other "u";
               hashes = [];
               provided_packages =
                 [
                   opam_factory ~name:"d" ~version:"zdev";
                   opam_factory ~name:"d-lwt" ~version:"zdev";
                 ];
             })
        ();
      make_test ~name:"An empty string dev_repo results in an error"
        ~dev_repo:"" ~packages:[]
        ~expected:
          (Rresult.R.error_msgf
             "unexpected empty string while computing name for dev_repo: \"%s\""
             "")
        ();
    ]
end

let test_from_dependency_entries =
  let make_test ~name ?(get_default_branch = fun _ -> assert false)
      ~dependency_entries ~expected () =
    let test_name = Printf.sprintf "from_dependency_entries: %s" name in
    let test_fun () =
      let actual =
        Duniverse.from_dependency_entries ~get_default_branch dependency_entries
      in
      Alcotest.(check (result (list Testable.Repo.unresolved) Testable.r_msg))
        test_name expected actual
    in
    (test_name, `Quick, test_fun)
  in
  [
    make_test ~name:"Empty" ~dependency_entries:[] ~expected:(Ok []) ();
    make_test ~name:"Filters virtual"
      ~dependency_entries:[ dependency_factory ?dev_repo:None () ]
      ~expected:(Ok []) ();
    make_test ~name:"Filters base packages"
      ~dependency_entries:
        [
          dependency_factory ~dev_repo:"d" ~url_src:(Other "u") ~name:"dune" ();
        ]
      ~expected:(Ok []) ();
    make_test ~name:"Simple"
      ~dependency_entries:
        [
          dependency_factory ~name:"x" ~version:"v" ~url_src:(Other "u")
            ~dev_repo:"d" ~hashes:[] ~has_build_commands:true ();
        ]
      ~expected:
        (Ok
           [
             {
               dir = "d";
               url = Other "u";
               hashes = [];
               provided_packages = [ opam_factory ~name:"x" ~version:"v" ];
             };
           ])
      ();
    make_test ~name:"Package with just install commands"
      ~dependency_entries:
        [
          dependency_factory ~name:"x" ~version:"v" ~url_src:(Other "u")
            ~dev_repo:"d" ~hashes:[] ~has_install_commands:true ();
        ]
      ~expected:
        (Ok
           [
             {
               dir = "d";
               url = Other "u";
               hashes = [];
               provided_packages = [ opam_factory ~name:"x" ~version:"v" ];
             };
           ])
      ();
    make_test ~name:"Non-vendored"
      ~dependency_entries:
        [
          dependency_factory ~vendored:false ~dev_repo:"d" ~url_src:(Other "u")
            ~name:"y" ~version:"v" ();
        ]
      ~expected:(Ok []) ();
    make_test ~name:"Aggregates repos"
      ~dependency_entries:
        [
          dependency_factory ~name:"y" ~version:"v" ~url_src:(Other "u")
            ~dev_repo:"d" ~hashes:[] ~has_build_commands:true ();
          dependency_factory ~name:"y-lwt" ~version:"v" ~url_src:(Other "u")
            ~dev_repo:"d" ~hashes:[] ~has_build_commands:true ();
        ]
      ~expected:
        (Ok
           [
             {
               dir = "d";
               url = Other "u";
               hashes = [];
               provided_packages =
                 [
                   opam_factory ~name:"y-lwt" ~version:"v";
                   opam_factory ~name:"y" ~version:"v";
                 ];
             };
           ])
      ();
    make_test ~name:"Excludes compilers"
      ~dependency_entries:
        [
          dependency_factory ~name:"mycaml" ~version:"5" ~url_src:(Other "u")
            ~dev_repo:"d" ~flags:[ Flag.compiler ] ();
        ]
      ~expected:(Ok []) ();
    make_test ~name:"Excludes anything that is a compiler"
      ~dependency_entries:
        [
          dependency_factory ~name:"conf-mycaml" ~version:"5"
            ~url_src:(Other "u") ~dev_repo:"d"
            ~flags:[ Flag.compiler; Flag.conf ]
            ();
        ]
      ~expected:(Ok []) ();
  ]

let suite =
  ( "Duniverse",
    List.concat
      [
        Repo.Package.test_from_package_summary;
        Repo.test_from_packages;
        test_from_dependency_entries;
      ] )
