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
module Builder = MessageBuilder.Make(GenCommon.M)

let sprintf = Printf.sprintf
let apply_indent = GenCommon.apply_indent


(* Generate an encoder lambda for converting from an enum value to the associated
   uint16.  [allow_undefined] indicates whether or not to permit enum values which
   use the [Undefined_] constructor. *)
let generate_enum_encoder_lines ~(allow_undefined : bool) ~nodes_table ~scope
    ~enum_node ~indent =
  let header = [ "(fun enum -> match enum with" ] in
  let scope_relative_name =
    GenCommon.get_scope_relative_name nodes_table scope enum_node
  in
  let match_cases =
    let enumerants =
      match PS.Node.unnamed_union_get enum_node with
      | PS.Node.Enum enum_group ->
          PS.Node.Enum.enumerants_get enum_group
      | _ ->
          failwith "Decoded non-enum node where enum node was expected."
    in
    let rec loop_cases acc i =
      if i = R.Array.length enumerants then
        List.rev acc
      else
        let enumerant = R.Array.get enumerants i in
        let case_str =
          sprintf "  | %s.%s -> %u"
            scope_relative_name
            (String.capitalize (PS.Enumerant.name_get enumerant))
            i
        in
        loop_cases (case_str :: acc) (i + 1)
    in
    loop_cases [] 0
  in
  let footer = 
    if allow_undefined then [
      sprintf " | %s.Undefined_ x -> x)" scope_relative_name
    ] else [
        sprintf "  | %s.Undefined_ _ ->" scope_relative_name;
                "      invalid_msg \"Cannot encode undefined enum value.\")";
    ]
  in
  apply_indent ~indent (header @ match_cases @ footer)


(* FIXME: get rid of this *)
let generate_enum_encoder ~(allow_undefined : bool) ~nodes_table ~scope
    ~enum_node ~indent ~field_ofs =
  (String.concat ~sep:"\n" (generate_enum_encoder_lines ~allow_undefined
      ~nodes_table ~scope ~enum_node ~indent)) ^ "\n"


(* Generate an accessor for decoding an enum type. *)
let generate_enum_getter ~nodes_table ~scope ~enum_node ~indent ~field_name
    ~field_ofs ~default =
  let decoder_lambda = GenReader.generate_enum_decoder_lines ~nodes_table ~scope
      ~enum_node ~indent:(indent ^ "    ")
  in
  let lines = [
    "let " ^ field_name ^ "_get x =";
    "  let decode ="; ] @ decoder_lambda @ [
    "  in";
    sprintf "  decode (get_data_field x ~f:(get_uint16 ~default:%u ~byte_ofs:%u))"
      default (field_ofs * 2);
  ] in
  apply_indent ~indent lines


(* Generate an accessor for setting the value of an enum. *)
let generate_enum_safe_setter ~nodes_table ~scope ~enum_node ~indent ~field_name
    ~field_ofs ~default ~discr_str =
  let encoder_lambda = generate_enum_encoder_lines ~allow_undefined:false
      ~nodes_table ~scope ~enum_node
      ~indent:(indent ^ "    ")
  in
  let lines = [
    "let " ^ field_name ^ "_set x e =";
    "  let encode =" ] @ encoder_lambda @ [
    "  in";
    sprintf
      "  get_data_field %sx ~f:(set_uint16 ~default:%u ~byte_ofs:%u (encode e))"
      discr_str
      default
      (field_ofs * 2);
  ] in
  apply_indent ~indent lines


(* Generate an accessor for setting the value of an enum, permitting values
   which are not defined in the schema. *)
let generate_enum_unsafe_setter ~nodes_table ~scope ~enum_node ~indent
    ~field_name ~field_ofs ~default ~discr_str =
  let encoder_lambda = generate_enum_encoder_lines ~allow_undefined:true
      ~nodes_table ~scope ~enum_node
      ~indent:(indent ^ "    ")
  in
  let lines = [
    "let " ^ field_name ^ "_set_unsafe x e =";
    "  let encode =" ] @ encoder_lambda @ [
    "  in";
    sprintf
      "  get_data_field %sx ~f:(set_uint16 ~default:%u ~byte_ofs:%u (encode e))"
      discr_str
      default
      (field_ofs * 2);
  ] in
  apply_indent ~indent lines


(* Generate an accessor for retrieving a list of the given type. *)
let generate_list_accessor ~nodes_table ~scope ~list_type ~indent
    ~field_name ~field_ofs ~discr_str =
  let make_accessors type_str =
    apply_indent ~indent [
      sprintf "let %s_get x = get_pointer_field x %u ~f:get_%s_list"
        field_name field_ofs type_str;
      sprintf "let %s_set x v = get_pointer_field %sx %u ~f:(set_%s_list v)"
        field_name discr_str field_ofs type_str;
      sprintf "let %s_init x n = get_pointer_field %sx %u ~f:(init_%s_list n)"
        field_name discr_str field_ofs type_str;
    ]
  in
  match PS.Type.unnamed_union_get list_type with
  | PS.Type.Void ->
      make_accessors "void"
  | PS.Type.Bool ->
      make_accessors "bit"
  | PS.Type.Int8 ->
      make_accessors "int8"
  | PS.Type.Int16 ->
      make_accessors "int16"
  | PS.Type.Int32 ->
      make_accessors "int32"
  | PS.Type.Int64 ->
      make_accessors "int64"
  | PS.Type.Uint8 ->
      make_accessors "uint8"
  | PS.Type.Uint16 ->
      make_accessors "uint16"
  | PS.Type.Uint32 ->
      make_accessors "uint32"
  | PS.Type.Uint64 ->
      make_accessors "uint64"
  | PS.Type.Float32 ->
      make_accessors "float32"
  | PS.Type.Float64 ->
      make_accessors "float64"
  | PS.Type.Text ->
      make_accessors "text"
  | PS.Type.Data ->
      make_accessors "blob"
  | PS.Type.List _ ->
      make_accessors "list"
  | PS.Type.Enum enum_def ->
      let enum_id = PS.Type.Enum.typeId_get enum_def in
      let enum_node = Hashtbl.find_exn nodes_table enum_id in
      let decoder_declaration =
        let decoder_lambda = GenReader.generate_enum_decoder_lines ~nodes_table
            ~scope ~enum_node ~indent:"  "
        in
        let lines = [
          "let decode = "; ] @ decoder_lambda @ [
          "in";
        ] in
        apply_indent ~indent:"  " lines
      in
      let encoder_declaration =
        let encoder_lambda = generate_enum_encoder_lines ~allow_undefined:false
            ~nodes_table ~scope ~enum_node ~indent:"  "
        in
        let lines = [
          "let encode = "; ] @ encoder_lambda @ [
          "in";
        ] in
        apply_indent ~indent:"  " lines
      in
      let codecs_declaration = [
        "let codecs ="; ] @ decoder_declaration @ encoder_declaration @ [
        "in";
      ] in
      let lines = [
        "let " ^ field_name ^ "_get x ="; ] @ codecs_declaration @ [
        sprintf
          "  get_pointer_field x %u ~f:(get_list \
             ~storage_type:ListStorage.Bytes2 ~codecs)"
          (field_ofs * 2);
        "let " ^ field_name ^ "_set x v ="; ] @ codecs_declaration @ [
        sprintf
          "  get_pointer_field x %u ~f:(set_list \
             ~storage_type:ListStorage.Bytes2 ~codecs v)"
          (field_ofs * 2);
        "let " ^ field_name ^ "_init x n ="; ] @ codecs_declaration @ [
        sprintf
          "  get_pointer_field x %u ~f:(init_list \
             ~storage_type:ListStorage.Bytes2 ~codecs n)"
          (field_ofs * 2);
      ] in
      apply_indent ~indent lines
  | PS.Type.Struct struct_def ->
      let id = PS.Type.Struct.typeId_get struct_def in
      let node = Hashtbl.find_exn nodes_table id in
      begin match PS.Node.unnamed_union_get node with
      | PS.Node.Struct struct_def' ->
          let data_words    = PS.Node.Struct.dataWordCount_get struct_def' in
          let pointer_words = PS.Node.Struct.pointerCount_get struct_def' in
          apply_indent ~indent [
            sprintf
              "let %s_get x = get_pointer_field x %u \
               ~f:(get_struct_list ~data_words:%u ~pointer_words:%u)"
              field_name field_ofs data_words pointer_words;
            sprintf
              "let %s_set x v = get_pointer_field %sx %u \
               ~f:(set_struct_list ~data_words:%u ~pointer_words:%u v)"
              field_name discr_str field_ofs data_words pointer_words;
            sprintf
              "let %s_init x n = get_pointer_field %sx %u \
               ~f:(init_struct_list ~data_words:%u ~pointer_words:%u n)"
              field_name discr_str field_ofs data_words pointer_words;
          ]
      | _ ->
          failwith "decoded non-struct node where struct node was expected."
      end
  | PS.Type.Interface _ ->
      apply_indent ~indent [
        "let " ^ field_name ^ "_get x = failwith \"not implemented\"";
        "let " ^ field_name ^ "_set x v = failwith \"not implemented\"";
        "let " ^ field_name ^ "_init x n = failwith \"not implemented\"";
      ]
  | PS.Type.AnyPointer ->
      apply_indent ~indent [
        "let " ^ field_name ^ "_get x = failwith \"not implemented\"";
        "let " ^ field_name ^ "_set x v = failwith \"not implemented\"";
        "let " ^ field_name ^ "_init x n = failwith \"not implemented\"";
      ]
  | PS.Type.Undefined_ x ->
       failwith (sprintf "Unknown Type union discriminant %d" x)


(* FIXME: would be nice to unify default value logic with [generate_constant]... *)
let generate_field_accessors ~nodes_table ~scope ~indent ~discr_ofs field =
  let field_name = String.uncapitalize (PS.Field.name_get field) in
  let discriminant_value = PS.Field.discriminantValue_get field in
  let discr_str =
    if discriminant_value = PS.Field.noDiscriminant then
      ""
    else
      sprintf "~discr:{Discr.value=%u; Discr.byte_ofs=%u} "
        discriminant_value (discr_ofs * 2)
  in
  match PS.Field.unnamed_union_get field with
  | PS.Field.Group group ->
      apply_indent ~indent [
        "let " ^ field_name ^ "_get x = x";
        (* So group setters look unexpectedly complicated.  [x] is the parent struct
         * which contains the group to be modified, and [v] is another struct which
         * contains the group with values to be copied.  The resulting operation
         * should merge the group fields from [v] into the proper place in struct [x]. *)
        (* FIXME: based on C++ runtime, these should not be emitted at all. *)
        "let " ^ field_name ^ "_set x v = failwith \"not implemented\"";
        "let " ^ field_name ^ "_init x n = failwith \"not implemented\"";
      ]
  | PS.Field.Slot slot ->
      let field_ofs = Uint32.to_int (PS.Field.Slot.offset_get slot) in
      let tp = PS.Field.Slot.type_get slot in
      let default = PS.Field.Slot.defaultValue_get slot in
      begin match (PS.Type.unnamed_union_get tp,
        PS.Value.unnamed_union_get default) with
      | (PS.Type.Void, PS.Value.Void) ->
          apply_indent ~indent [
            "let " ^ field_name ^ "_get x = ()";
            sprintf "let %s_set x = get_data_field %sx ~f:set_void"
              field_name discr_str;
          ]
      | (PS.Type.Bool, PS.Value.Bool a) ->
          apply_indent ~indent [
            sprintf
              "let %s_get x = get_data_field x \
               ~f:(get_bit ~default:%s ~byte_ofs:%u ~bit_ofs:%u)"
              field_name
              (if a then "true" else "false")
              (field_ofs / 8)
              (field_ofs mod 8);
            sprintf
              "let %s_set x v = get_data_field %sx \
               ~f:(set_bit ~default:%s ~byte_ofs:%u ~bit_ofs:%u v)"
              field_name
              discr_str
              (if a then "true" else "false")
              (field_ofs / 8)
              (field_ofs mod 8);
          ]
      | (PS.Type.Int8, PS.Value.Int8 a) ->
          apply_indent ~indent [
            sprintf
              "let %s_get x = get_data_field x \
               ~f:(get_int8 ~default:%d ~byte_ofs:%u)"
              field_name a field_ofs;
            sprintf
              "let %s_set x v = get_data_field %sx \
               ~f:(set_int8 ~default:%d ~byte_ofs:%u v)"
              field_name discr_str a field_ofs;
          ]
      | (PS.Type.Int16, PS.Value.Int16 a) ->
          apply_indent ~indent [
            sprintf
              "let %s_get x = get_data_field x \
               ~f:(get_int16 ~default:%d ~byte_ofs:%u)"
              field_name a (field_ofs * 2);
            sprintf
              "let %s_set x v = get_data_field %sx \
               ~f:(set_int16 ~default:%d ~byte_ofs:%u v)"
              field_name discr_str a (field_ofs * 2);
          ]
      | (PS.Type.Int32, PS.Value.Int32 a) ->
          apply_indent ~indent [
            sprintf
              "let %s_get x = get_data_field x \
               ~f:(get_int32 ~default:%sl ~byte_ofs:%u)"
              field_name (Int32.to_string a) (field_ofs * 4);
            sprintf
              "let %s_get_int_exn x = Int32.to_int (%s_get x)"
              field_name field_name;
            sprintf
              "let %s_set x v = get_data_field %sx \
               ~f:(set_int32 ~default:%sl ~byte_ofs:%u v)"
              field_name discr_str (Int32.to_string a) (field_ofs * 4);
            sprintf
              "let %s_set_int_exn x v = %s_set x (Int32.of_int v)"
              field_name field_name;
          ]
      | (PS.Type.Int64, PS.Value.Int64 a) ->
          apply_indent ~indent [
            sprintf
              "let %s_get x = get_data_field x \
               ~f:(get_int64 ~default:%sL ~byte_ofs:%u)"
              field_name (Int64.to_string a) (field_ofs * 8);
            sprintf
              "let %s_get_int_exn x = Int64.to_int (%s_get x)"
              field_name field_name;
            sprintf
              "let %s_set x v = get_data_field %sx \
               ~f:(set_int64 ~default:%sL ~byte_ofs:%u v)"
              field_name discr_str (Int64.to_string a) (field_ofs * 8);
            sprintf
              "let %s_set_int_exn x v = %s_set x (Int64.of_int v)"
              field_name field_name;
          ]
      | (PS.Type.Uint8, PS.Value.Uint8 a) ->
          apply_indent ~indent [
            sprintf
              "let %s_get x = get_data_field x \
               ~f:(get_uint8 ~default:%d ~byte_ofs:%u)"
              field_name a field_ofs;
            sprintf
              "let %s_set x v = get_data_field %sx \
               ~f:(set_uint8 ~default:%d ~byte_ofs:%u v)"
              field_name discr_str a field_ofs;
          ]
      | (PS.Type.Uint16, PS.Value.Uint16 a) ->
          apply_indent ~indent [
            sprintf
              "let %s_get x = get_data_field x \
               ~f:(get_uint16 ~default:%d ~byte_ofs:%u)"
              field_name a field_ofs;
            sprintf
              "let %s_set x v = get_data_field %sx \
               ~f:(set_uint16 ~default:%d ~byte_ofs:%u v)"
              field_name discr_str a field_ofs;
          ]
      | (PS.Type.Uint32, PS.Value.Uint32 a) ->
          let default =
            if Uint32.compare a Uint32.zero = 0 then
              "Uint32.zero"
            else
              sprintf "(Uint32.of_string \"%s\")" (Uint32.to_string a)
          in
          apply_indent ~indent [
            sprintf
              "let %s_get x = get_data_field x \
               ~f:(get_uint32 ~default:%s ~byte_ofs:%u)"
              field_name default (field_ofs * 4);
            sprintf
              "let %s_get_int_exn x = Uint32.to_int (%s_get x)"
              field_name field_name;
            sprintf
              "let %s_set x v = get_data_field %sx \
               ~f:(set_uint32 ~default:%s ~byte_ofs:%u v)"
              field_name discr_str default (field_ofs * 4);
            sprintf
              "let %s_set_int_exn x v = %s_set x (Uint32.of_int v)"
              field_name field_name;
          ]
      | (PS.Type.Uint64, PS.Value.Uint64 a) ->
          let default =
            if Uint64.compare a Uint64.zero = 0 then
              "Uint64.zero"
            else
              sprintf "(Uint64.of_string \"%s\")" (Uint64.to_string a)
          in
          apply_indent ~indent [
            sprintf
              "let %s_get x = get_data_field x \
               ~f:(get_uint64 ~default:%s ~byte_ofs:%u)"
              field_name default (field_ofs * 8);
            sprintf
              "let %s_get_int_exn x = Uint64.to_int (%s_get x)"
              field_name field_name;
            sprintf
              "let %s_set x v = get_data_field %sx \
               ~f:(set_uint64 ~default:%s ~byte_ofs:%u v)"
              field_name discr_str default (field_ofs * 8);
            sprintf
              "let %s_set_int_exn x v = %s_set x (Uint64.of_int v)"
              field_name field_name;
          ]
      | (PS.Type.Float32, PS.Value.Float32 a) ->
          let default_int32 = Int32.bits_of_float a in
          apply_indent ~indent [
            sprintf
              "let %s_get x = get_data_field x \
               ~f:(get_float32 ~default_bits:%sl ~byte_ofs:%u)"
              field_name (Int32.to_string default_int32) (field_ofs * 4);
            sprintf
              "let %s_set x v = get_data_field %sx \
               ~f:(set_float32 ~default_bits:%sl ~byte_ofs:%u v)"
              field_name discr_str (Int32.to_string default_int32) (field_ofs * 4);
          ]
      | (PS.Type.Float64, PS.Value.Float64 a) ->
          let default_int64 = Int64.bits_of_float a in
          apply_indent ~indent [
            sprintf
              "let %s_get x = get_data_field x \
               ~f:(get_float64 ~default_bits:%sL ~byte_ofs:%u)"
              field_name (Int64.to_string default_int64) (field_ofs * 8);
            sprintf
              "let %s_set x v = get_data_field %sx \
               ~f:(set_float64 ~default_bits:%sL ~byte_ofs:%u v)"
              field_name discr_str (Int64.to_string default_int64) (field_ofs * 8);
          ]
      | (PS.Type.Text, PS.Value.Text a) ->
          apply_indent ~indent [
            sprintf
              "let %s_get x = get_pointer_field x %u \
               ~f:(get_text ~default:\"%s\")"
              field_name field_ofs (String.escaped a);
            sprintf
              "let %s_set x v = get_pointer_field %sx %u ~f:(set_text v)"
              field_name discr_str field_ofs
          ]
      | (PS.Type.Data, PS.Value.Data a) ->
          apply_indent ~indent [
            sprintf
              "let %s_get x = get_pointer_field x %u \
               ~f:(get_blob ~default:\"%s\")"
              field_name field_ofs (String.escaped a);
            sprintf
              "let %s_set x v = get_pointer_field %sx %u ~f:(set_blob v)"
              field_name discr_str field_ofs
          ]
      | (PS.Type.List list_def, PS.Value.List pointer_slice_opt) ->
          let has_trivial_default =
            begin match pointer_slice_opt with
            | Some pointer_slice ->
                begin match Builder.decode_pointer pointer_slice with
                | Pointer.Null -> true
                | _ -> false
                end
            | None ->
                true
            end
          in
          if has_trivial_default then
            let list_type = PS.Type.List.elementType_get list_def in
            generate_list_accessor ~nodes_table ~scope ~list_type ~indent
              ~field_name ~field_ofs ~discr_str
          else
            failwith "Default values for lists are not implemented."
      | (PS.Type.Enum enum_def, PS.Value.Enum val_uint16) ->
          let enum_id = PS.Type.Enum.typeId_get enum_def in
          let enum_node = Hashtbl.find_exn nodes_table enum_id in
          (generate_enum_getter
            ~nodes_table ~scope ~enum_node ~indent ~field_name ~field_ofs
            ~default:val_uint16) @
          (generate_enum_safe_setter
            ~nodes_table ~scope ~enum_node ~indent ~field_name ~field_ofs
            ~default:val_uint16 ~discr_str) @
          (generate_enum_unsafe_setter
            ~nodes_table ~scope ~enum_node ~indent ~field_name ~field_ofs
            ~default:val_uint16 ~discr_str)
      | (PS.Type.Struct struct_def, PS.Value.Struct pointer_slice_opt) ->
          let has_trivial_default =
            begin match pointer_slice_opt with
            | Some pointer_slice ->
                begin match Builder.decode_pointer pointer_slice with
                | Pointer.Null -> true
                | _ -> false
                end
            | None ->
                true
            end
          in
          if has_trivial_default then
            let id = PS.Type.Struct.typeId_get struct_def in
            let node = Hashtbl.find_exn nodes_table id in
            match PS.Node.unnamed_union_get node with
            | PS.Node.Struct struct_def' ->
                let data_words =
                  PS.Node.Struct.dataWordCount_get struct_def'
                in
                let pointer_words =
                  PS.Node.Struct.pointerCount_get struct_def'
                in 
                apply_indent ~indent [
                  sprintf
                    "let %s_get x = get_pointer_field x %u \
                     ~f:(get_struct ~data_words:%u ~pointer_words:%u)"
                    field_name field_ofs data_words pointer_words;
                  sprintf
                    "let %s_set x v = get_pointer_field %sx %u \
                     ~f:(set_struct ~data_words:%u ~pointer_words:%u v)"
                    field_name discr_str field_ofs
                    data_words pointer_words;
                  sprintf
                    "let %s_init x = get_pointer_field %sx %u \
                     ~f:(init_struct ~data_words:%u ~pointer_words:%u)"
                    field_name discr_str field_ofs
                    data_words pointer_words;
                ]
            | _ ->
                failwith
                  "decoded non-struct node where struct node was expected."
          else
            failwith "Default values for structs are not implemented."
      | (PS.Type.Interface iface_def, PS.Value.Interface) ->
          apply_indent ~indent [
            "let " ^ field_name ^ "_get x = failwith \"not implemented\"";
            "let " ^ field_name ^ "_set x v = failwith \"not implemented\"";
            "let " ^ field_name ^ "_init x = failwith \"not implemented\"";
          ]
      | (PS.Type.AnyPointer, PS.Value.AnyPointer pointer) ->
          apply_indent ~indent [
            sprintf "let %s_get x = get_pointer_field x %u ~f:(fun s -> s)"
              field_name field_ofs;
            "let " ^ field_name ^ "_set x v = failwith \"not implemented\"";
          ]
      | (PS.Type.Undefined_ x, _) ->
          failwith (sprintf "Unknown Field union discriminant %u." x)

      (* All other cases represent an ill-formed default value in the plugin request *)
      | (PS.Type.Void, _)
      | (PS.Type.Bool, _)
      | (PS.Type.Int8, _)
      | (PS.Type.Int16, _)
      | (PS.Type.Int32, _)
      | (PS.Type.Int64, _)
      | (PS.Type.Uint8, _)
      | (PS.Type.Uint16, _)
      | (PS.Type.Uint32, _)
      | (PS.Type.Uint64, _)
      | (PS.Type.Float32, _)
      | (PS.Type.Float64, _)
      | (PS.Type.Text, _)
      | (PS.Type.Data, _)
      | (PS.Type.List _, _)
      | (PS.Type.Enum _, _)
      | (PS.Type.Struct _, _)
      | (PS.Type.Interface _, _)
      | (PS.Type.AnyPointer, _) ->
          let err_msg = sprintf
              "The default value for field \"%s\" has an unexpected type."
              field_name
          in
          failwith err_msg
      end
  | PS.Field.Undefined_ x ->
      failwith (sprintf "Unknown Field union discriminant %u." x)


(* Generate accessors for retrieving all fields of a struct, regardless of whether
 * or not the fields are packed into a union.  (Fields packed inside a union are
 * not exposed in the module signature. *)
let generate_accessors ~nodes_table ~scope struct_def fields =
  let indent = String.make (2 * (List.length scope + 2)) ' ' in
  let discr_ofs = Uint32.to_int (PS.Node.Struct.discriminantOffset_get struct_def) in
  List.fold_left fields ~init:[] ~f:(fun acc field ->
    let x = generate_field_accessors ~nodes_table ~scope ~indent ~discr_ofs field in
    x @ acc)


(* Generate a function for unpacking a capnp union type as an OCaml variant. *)
let generate_union_accessor_lines ~nodes_table ~scope struct_def fields : string list =
  let indent = String.make (2 * (List.length scope + 2)) ' ' in
  let cases = List.fold_left fields ~init:[] ~f:(fun acc field ->
    let field_name = String.uncapitalize (PS.Field.name_get field) in
    let ctor_name = String.capitalize field_name in
    let field_value = PS.Field.discriminantValue_get field in
    let field_has_void_type =
      match PS.Field.unnamed_union_get field with
      | PS.Field.Slot slot ->
          begin match PS.Type.unnamed_union_get (PS.Field.Slot.type_get slot) with
          | PS.Type.Void -> true
          | _ -> false
          end
      | _ -> false
    in
    if field_has_void_type then
      (sprintf "%s  | %u -> %s"
        indent
        field_value
        ctor_name) :: acc
    else
      (sprintf "%s  | %u -> %s (%s_get x)"
        indent
        field_value
        ctor_name
        field_name) :: acc)
  in
  let header = apply_indent ~indent [
      "let unnamed_union_get x =";
      sprintf 
        "  match get_data_field x ~f:(get_uint16 ~default:0 ~byte_ofs:%u) with"
        ((Uint32.to_int (PS.Node.Struct.discriminantOffset_get struct_def)) * 2);
    ] in
  let footer = [ indent ^ "  | v -> Undefined_ v" ] in
  (GenCommon.generate_union_type_lines ~mode:Mode.Reader nodes_table scope
     struct_def fields) @ header @ cases @ footer


(* FIXME: get rid of this *)
let generate_union_accessor ~nodes_table ~scope struct_def fields =
  (String.concat ~sep:"\n"
     (generate_union_accessor_lines ~nodes_table ~scope struct_def fields)) ^ "\n"


(* Generate the OCaml module corresponding to a struct definition.  [scope] is a
 * stack of scope IDs corresponding to this lexical context, and is used to figure
 * out what module prefixes are required to properly qualify a type.
 *
 * Raises: Failure if the children of this node contain a cycle. *)
let rec generate_struct_node ~nodes_table ~scope ~nested_modules ~node struct_def =
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
  let union_fields = List.filter all_fields ~f:(fun field ->
    (PS.Field.discriminantValue_get field) <> PS.Field.noDiscriminant)
  in
  let accessors : string list =
    generate_accessors ~nodes_table ~scope struct_def all_fields
  in
  let union_accessors =
    match union_fields with
    | [] ->
        []
    | _  ->
        (generate_union_accessor_lines ~nodes_table ~scope struct_def union_fields)
  in
  let data_words    = PS.Node.Struct.dataWordCount_get struct_def in
  let pointer_words = PS.Node.Struct.pointerCount_get struct_def in
  let indent = String.make (2 * (List.length scope + 2)) ' ' in
  let header = apply_indent ~indent [
    "type t = rw StructStorage.t";
    sprintf "type %s = t"
      (GenCommon.make_unique_typename ~mode:Mode.Builder
         ~scope_mode:Mode.Builder ~nodes_table node);
    sprintf "type reader_t = Reader.%s.t"
      (GenCommon.get_fully_qualified_name nodes_table node);
    sprintf "type %s = reader_t"
      (GenCommon.make_unique_typename ~mode:Mode.Reader
         ~scope_mode:Mode.Builder ~nodes_table node);
    "type array_t = rw ListStorage.t";
    "type reader_array_t = ro ListStorage.t";
    ] in
  let footer = apply_indent ~indent [
      sprintf
        "let of_message x = get_root_struct ~data_words:%u ~pointer_words:%u x"
        data_words pointer_words;
    ] in
  header @ nested_modules @ accessors @ union_accessors @ footer


(* Generate the OCaml module and type signature corresponding to a node.  [scope] is
 * a stack of scope IDs corresponding to this lexical context, and is used to figure out
 * what module prefixes are required to properly qualify a type.
 *
 * Raises: Failure if the children of this node contain a cycle. *)
and generate_node
    ~(suppress_module_wrapper : bool)
    ~(nodes_table : (Uint64.t, PS.Node.t) Hashtbl.t)
    ~(scope : Uint64.t list)
    ~(node_name : string)
    (node : PS.Node.t)
  : string list =
  let node_id = PS.Node.id_get node in
  let indent = String.make (2 * (List.length scope + 1)) ' ' in
  let generate_nested_modules () : string list =
    match Topsort.topological_sort nodes_table
            (GenCommon.children_of nodes_table node) with
    | Some child_nodes ->
        List.concat_map child_nodes ~f:(fun child ->
          let child_name = GenCommon.get_unqualified_name ~parent:node ~child in
          let child_node_id = PS.Node.id_get child in
          generate_node ~suppress_module_wrapper:false ~nodes_table
            ~scope:(child_node_id :: scope) ~node_name:child_name child)
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
        generate_struct_node ~nodes_table ~scope ~nested_modules ~node struct_def
      in
      if suppress_module_wrapper then
        body
      else
        [ indent ^ "module " ^ node_name ^ " = struct" ] @
          body @
        [ indent ^ "end" ]
  | PS.Node.Enum enum_def ->
      let nested_modules = generate_nested_modules () in
      let body =
        GenCommon.generate_enum_sig_lines ~nodes_table ~scope ~nested_modules
          ~mode:GenCommon.Mode.Builder ~node enum_def
      in
      if suppress_module_wrapper then
        body
      else
        [ indent ^ "module " ^ node_name ^ " = struct" ] @
          body @
          [ indent ^ "end" ]
  | PS.Node.Interface iface_def ->
      generate_nested_modules ()
  | PS.Node.Const const_def ->
      apply_indent ~indent [
        "let " ^ (String.uncapitalize node_name) ^ " = " ^
          (GenCommon.generate_constant ~nodes_table ~scope const_def);
      ]
  | PS.Node.Annotation annot_def ->
      generate_nested_modules ()
  | PS.Node.Undefined_ x ->
      failwith (sprintf "Unknown Node union discriminant %u" x)

