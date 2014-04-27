(******************************************************************************
 * capnp-ocaml
 *
 * Copyright (c) 2013-2014, Paul Pelzl
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *  1. Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 *
 *  2. Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 ******************************************************************************)


open Core.Std

module PS = GenCommon.PS
module Mode = GenCommon.Mode
module R  = Runtime

let sprintf = Printf.sprintf
let apply_indent = GenCommon.apply_indent


(* Generate a function for unpacking a capnp union type as an OCaml variant. *)
let generate_union_accessors ~nodes_table ~scope ~mode struct_def fields =
  let indent = String.make (2 * (List.length scope + 2)) ' ' in
  (GenCommon.generate_union_type ~mode nodes_table scope fields) @
    [ indent ^ "val unnamed_union_get : t -> unnamed_union_t" ]


let generate_setters ~nodes_table ~scope fields =
  let indent = String.make (2 * (List.length scope + 2)) ' ' in
  List.fold_left fields ~init:[] ~f:(fun acc field ->
    let field_accessors : string list =
      let field_name = String.uncapitalize (PS.Field.name_get field) in
      match PS.Field.unnamed_union_get field with
      | PS.Field.Group group ->
          []
      | PS.Field.Slot slot ->
          let tp = PS.Field.Slot.type_get slot in
          begin match PS.Type.unnamed_union_get tp with
          | PS.Type.Int32 ->
              apply_indent ~indent [
                "val " ^ field_name ^ "_set : t -> int32 -> unit";
                "val " ^ field_name ^ "_set_int_exn : t -> int -> unit";
              ]
          | PS.Type.Int64 ->
              apply_indent ~indent [
                "val " ^ field_name ^ "_set : t -> int64 -> unit";
                "val " ^ field_name ^ "_set_int_exn : t -> int -> unit";
              ]
          | PS.Type.Uint32 ->
              apply_indent ~indent [
                "val " ^ field_name ^ "_set : t -> Uint32.t -> unit";
                "val " ^ field_name ^ "_set_int_exn : t -> int -> unit";
              ]
          | PS.Type.Uint64 ->
              apply_indent ~indent [
                "val " ^ field_name ^ "_set : t -> Uint64.t -> unit";
                "val " ^ field_name ^ "_set_int_exn : t -> int -> unit";
              ]
          | PS.Type.List _ ->
              apply_indent ~indent [
                (* FIXME: should allow setting from a Reader *)
                sprintf "val %s_set : t -> %s -> %s"
                  field_name
                  (GenCommon.type_name ~mode:Mode.Builder ~scope_mode:Mode.Builder
                     nodes_table scope tp)
                  (GenCommon.type_name ~mode:Mode.Builder ~scope_mode:Mode.Builder
                     nodes_table scope tp);
                sprintf "val %s_init : t -> int -> %s"
                  field_name
                  (GenCommon.type_name ~mode:Mode.Builder ~scope_mode:Mode.Builder
                     nodes_table scope tp);
              ]
          | PS.Type.Struct _ ->
              apply_indent ~indent [
                sprintf "val %s_set_reader : t -> %s -> %s"
                  field_name
                  (GenCommon.type_name ~mode:Mode.Reader ~scope_mode:Mode.Builder
                     nodes_table scope tp)
                  (GenCommon.type_name ~mode:Mode.Builder ~scope_mode:Mode.Builder
                     nodes_table scope tp);
                sprintf "val %s_set_builder : t -> %s -> %s"
                  field_name
                  (GenCommon.type_name ~mode:Mode.Builder ~scope_mode:Mode.Builder
                     nodes_table scope tp)
                  (GenCommon.type_name ~mode:Mode.Builder ~scope_mode:Mode.Builder
                     nodes_table scope tp);
                sprintf "val %s_init : t -> %s"
                  field_name
                  (GenCommon.type_name ~mode:Mode.Builder ~scope_mode:Mode.Builder
                     nodes_table scope tp);
              ]
          | PS.Type.Bool
          | PS.Type.Int8
          | PS.Type.Int16
          | PS.Type.Uint8
          | PS.Type.Uint16
          | PS.Type.Float32
          | PS.Type.Float64
          | PS.Type.Text
          | PS.Type.Data
          | PS.Type.Enum _
          | PS.Type.Interface _
          | PS.Type.AnyPointer ->
              apply_indent ~indent [
                sprintf "val %s_set : t -> %s -> unit"
                field_name
                (GenCommon.type_name ~mode:Mode.Reader ~scope_mode:Mode.Builder
                   nodes_table scope tp);
              ]
          | PS.Type.Void ->
              (* For void types, we suppress the argument *)
              [ indent ^ "val " ^ field_name ^ "_set : t -> unit" ]
          | PS.Type.Undefined_ x ->
              failwith (sprintf "Unknown Type union discriminant %d" x)
          end
      | PS.Field.Undefined_ x ->
          failwith (sprintf "Unknown Field union discriminant %d" x)
    in
    (field_accessors @ acc))


(* Generate accessors for retrieving all non-union fields of a struct. *)
let generate_getters ~nodes_table ~scope ~mode fields =
  let indent = String.make (2 * (List.length scope + 2)) ' ' in
  List.fold_left fields ~init:[] ~f:(fun acc field ->
    let field_accessors : string list =
      let field_name = String.uncapitalize (PS.Field.name_get field) in
      match PS.Field.unnamed_union_get field with
      | PS.Field.Group group ->
          let group_id = PS.Field.Group.typeId_get group in
          let group_node = Hashtbl.find_exn nodes_table group_id in
          let group_name = GenCommon.get_scope_relative_name nodes_table scope group_node in
          [ sprintf "%sval %s_get : t -> %s.t\n" indent field_name group_name ]
      | PS.Field.Slot slot ->
          let tp = PS.Field.Slot.type_get slot in
          begin match PS.Type.unnamed_union_get tp with
          | PS.Type.Int32 ->
              apply_indent ~indent [
                "val " ^ field_name ^ "_get : t -> int32";
                "val " ^ field_name ^ "_get_int_exn : t -> int";
              ]
          | PS.Type.Int64 ->
              apply_indent ~indent [
                "val " ^ field_name ^ "_get : t -> int64";
                "val " ^ field_name ^ "_get_int_exn : t -> int";
              ]
          | PS.Type.Uint32 ->
              apply_indent ~indent [
                "val " ^ field_name ^ "_get : t -> Uint32.t";
                "val " ^ field_name ^ "_get_int_exn : t -> int";
              ]
          | PS.Type.Uint64 ->
              apply_indent ~indent [
                "val " ^ field_name ^ "_get : t -> Uint64.t";
                "val " ^ field_name ^ "_get_int_exn : t -> int";
              ]
          | PS.Type.Void
          | PS.Type.Bool
          | PS.Type.Int8
          | PS.Type.Int16
          | PS.Type.Uint8
          | PS.Type.Uint16
          | PS.Type.Float32
          | PS.Type.Float64
          | PS.Type.Text
          | PS.Type.Data
          | PS.Type.List _
          | PS.Type.Enum _
          | PS.Type.Struct _
          | PS.Type.Interface _
          | PS.Type.AnyPointer ->
              apply_indent ~indent [
                sprintf "val %s_get : t -> %s\n"
                  field_name
                  (GenCommon.type_name ~mode ~scope_mode:mode nodes_table scope tp);
              ]
          | PS.Type.Undefined_ x ->
              failwith (sprintf "Unknown Type union discriminant %d" x)
          end
      | PS.Field.Undefined_ x ->
          failwith (sprintf "Unknown Field union discriminant %d" x)
    in
    (field_accessors @ acc))


(* Generate the OCaml type signature corresponding to a struct definition.  [scope] is a
 * stack of scope IDs corresponding to this lexical context, and is used to figure
 * out what module prefixes are required to properly qualify a type.
 *
 * Raises: Failure if the children of this node contain a cycle. *)
let rec generate_struct_node ~nodes_table ~scope ~nested_modules ~mode
    ~node struct_def : string list =
  let unsorted_fields =
    let fields_accessor = PS.Node.Struct.fields_get struct_def in
    let rec loop_fields acc i =
      if i = R.Array.length fields_accessor then
        acc
      else
        let field = R.Array.get fields_accessor i in
        loop_fields (field :: acc) (i + 1)
    in
    loop_fields [] 0
  in
  (* Sorting in reverse code order allows us to avoid a List.rev *)
  let all_fields = List.sort unsorted_fields ~cmp:(fun x y ->
    - (Int.compare (PS.Field.codeOrder_get x) (PS.Field.codeOrder_get y)))
  in
  let union_fields, non_union_fields = List.partition_tf all_fields ~f:(fun field ->
    (PS.Field.discriminantValue_get field) <> PS.Field.noDiscriminant)
  in
  let union_accessors =
    match union_fields with
    | [] ->
        []
    | _  ->
        let union_setters =
          if mode = Mode.Builder then
            generate_setters ~nodes_table ~scope union_fields
          else
            []
        in
        (generate_union_accessors ~nodes_table ~scope ~mode
           struct_def union_fields) @
        union_setters
  in
  let non_union_accessors =
    match non_union_fields with
    | [] ->
        []
    | _  ->
        let non_union_setters =
          if mode = Mode.Builder then
            generate_setters ~nodes_table ~scope non_union_fields
          else
            []
        in
        (generate_getters ~nodes_table ~scope ~mode non_union_fields) @
        non_union_setters
  in
  let indent = String.make (2 * (List.length scope + 2)) ' ' in
  let lines = [
    (* declare the primary type of the node *)
    if mode = Mode.Reader then
      "type t"
    else
      ("type t = Reader." ^
         (GenCommon.get_fully_qualified_name nodes_table node) ^ ".builder_t");
    (* declare a schema-unique type alias for type [t] *)
    "type " ^
       (GenCommon.make_unique_typename ~mode ~scope_mode:mode ~nodes_table node) ^
      " = t";
    (* declare the [builder_t] or [reader_t] type alias *)
    if mode = Mode.Reader then
      "type builder_t"
    else
      ("type reader_t = Reader." ^
         (GenCommon.get_fully_qualified_name nodes_table node) ^ ".t");
    (* declare a schema-unique type alias for [builder_t] or [reader_t] *)
    if mode = Mode.Reader then
      "type " ^
        (GenCommon.make_unique_typename ~mode:Mode.Builder
          ~scope_mode:mode ~nodes_table node) ^
        " = builder_t"
    else
        ("type " ^
          (GenCommon.make_unique_typename ~mode:Mode.Reader
             ~scope_mode:mode ~nodes_table node) ^
           " = reader_t");
    (* declare opaque types for array state *)
    "type array_t";
    if mode = Mode.Builder then
       sprintf "type reader_array_t = Reader.%s.array_t" 
         (GenCommon.get_fully_qualified_name nodes_table node)
   else
     "";
  ] in
  (apply_indent ~indent lines) @
    nested_modules @
    union_accessors @
    non_union_accessors @
    [ indent ^ "val of_message : message_t -> t" ]


(* Generate the OCaml type signature corresponding to a node.  [scope] is
 * a stack of scope IDs corresponding to this lexical context, and is used to figure out
 * what module prefixes are required to properly qualify a type.
 *
 * Raises: Failure if the children of this node contain a cycle. *)
and generate_node
    ~(suppress_module_wrapper : bool)
    ~(nodes_table : (Uint64.t, PS.Node.t) Hashtbl.t)
    ~(scope : Uint64.t list)
    ~(node_name : string)
    ~(mode : GenCommon.Mode.t)
    (node : PS.Node.t)
: string list =
  let node_id = PS.Node.id_get node in
  let indent = String.make (2 * (List.length scope + 1)) ' ' in
  let generate_nested_modules () =
    match Topsort.topological_sort nodes_table
            (GenCommon.children_of nodes_table node) with
    | Some child_nodes ->
        List.concat_map child_nodes ~f:(fun child ->
          let child_name = GenCommon.get_unqualified_name ~parent:node ~child in
          let child_node_id = PS.Node.id_get child in
          generate_node ~suppress_module_wrapper:false ~nodes_table
            ~scope:(child_node_id :: scope) ~node_name:child_name child ~mode)
    | None ->
        let error_msg = sprintf
          "The children of node %s (%s) have a cyclic dependency."
          (Uint64.to_string node_id)
          (PS.Node.displayName_get node)
        in
        failwith error_msg
  in
  match PS.Node.unnamed_union_get node with
  | PS.Node.File ->
      generate_nested_modules ()
  | PS.Node.Struct struct_def ->
      let nested_modules = generate_nested_modules () in
      let body =
        generate_struct_node ~nodes_table ~scope ~nested_modules
          ~mode ~node struct_def
      in
      if suppress_module_wrapper then
        body
      else
        [ indent ^ "module " ^ node_name ^ " : sig" ] @
          body @
          [ indent ^ "end" ]
  | PS.Node.Enum enum_def ->
      let nested_modules = generate_nested_modules () in
      let body =
        GenCommon.generate_enum_sig ~nodes_table ~scope ~nested_modules
          ~mode ~node enum_def
      in
      if suppress_module_wrapper then
        body
      else
        [ indent ^ "module " ^ node_name ^ " : sig" ] @
          body @
          [ indent ^ "end" ]
  | PS.Node.Interface iface_def ->
      generate_nested_modules ()
  | PS.Node.Const const_def -> [
      sprintf "%sval %s : %s\n"
        indent
        (String.uncapitalize node_name)
        (GenCommon.type_name ~mode ~scope_mode:mode nodes_table scope
           (PS.Node.Const.type_get const_def));
    ]
  | PS.Node.Annotation annot_def ->
      generate_nested_modules ()
  | PS.Node.Undefined_ x ->
      failwith (sprintf "Unknown Node union discriminant %u" x)



