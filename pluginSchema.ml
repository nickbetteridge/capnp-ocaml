
module Make (Storage : MessageStorage.S) = struct
  module Reader = MessageReader.Make(Storage)
  open Reader

  module M = Message.Make(Storage)
  let invalid_msg = Message.invalid_msg
  open M

  (* FIXME: this needs to be namespaced somehow... *)
  module List = struct
    type ('cap, 'a) list_t = {
      storage  : 'cap ListStorage.t;
      get_item : 'cap ListStorage.t -> int -> 'a;
    }

    type ('cap, 'a) t = ('cap, 'a) list_t option

    let length (x : ('cap, 'a)  t) : int =
      match x with
      | Some {storage; _} ->
          storage.ListStorage.num_elements
      | None ->
          0

    let get (x : ('cap, 'a) t) (i : int) : 'a =
      match x with
      | Some {storage; get_item;} ->
          get_item storage i
      | None ->
          invalid_arg "index out of bounds"

  end

  module ElementSize = struct
    type t =
      | Empty
      | Bit
      | Byte
      | TwoBytes
      | FourBytes
      | EightBytes
      | Pointer
      | InlineComposite
  end

  module Value = struct
    type 'cap t = 'cap StructStorage.t option

    type 'cap unnamed_union_t =
      | Void
      | Bool of bool
      | Int8 of int
      | Int16 of int
      | Int32 of Int32.t
      | Int64 of Int64.t
      | Uint8 of int
      | Uint16 of int
      | Uint32 of Uint32.t
      | Uint64 of Uint64.t
      | Float32 of float
      | Float64 of float
      | Text of string
      | Data of string
      | List of 'cap Slice.t option
      | Enum of int
      | Struct of 'cap Slice.t option
      | Interface
      | Object of 'cap Slice.t option

    let unnamed_union_get (x : 'cap t) : 'cap unnamed_union_t =
      let tag = Util.decode_uint16_le (make_struct_byte_reader x 0 2) in
      match tag with
      | 0  -> Void
      | 1  -> Bool (get_struct_bit x 2 0)
      | 2  -> Int8 (Util.decode_int8 (make_struct_byte_reader x 2 1))
      | 3  -> Int16 (Util.decode_int16_le (make_struct_byte_reader x 2 2))
      | 4  -> Int32 (Util.decode_int32_le (make_struct_byte_reader x 4 4))
      | 5  -> Int64 (Util.decode_int64_le (make_struct_byte_reader x 8 8))
      | 6  -> Uint8 ((make_struct_byte_reader x 2 1) 0)
      | 7  -> Uint16 (Util.decode_uint16_le (make_struct_byte_reader x 2 2))
      | 8  -> Uint32 (Util.decode_uint32_le (make_struct_byte_reader x 4 4))
      | 9  -> Uint64 (Util.decode_uint64_le (make_struct_byte_reader x 8 8))
      | 10 -> Float32 (Int32.float_of_bits (Util.decode_int32_le (make_struct_byte_reader x 4 4)))
      | 11 -> Float64 (Int64.float_of_bits (Util.decode_int64_le (make_struct_byte_reader x 8 8)))
      | 12 -> Text (get_struct_text_field x 0)
      | 13 -> Data (get_struct_text_field x 0)
      | 14 -> List (get_struct_pointer x 0)
      | 15 -> Enum (Util.decode_uint16_le (make_struct_byte_reader x 2 2))
      | 16 -> Struct (get_struct_pointer x 0)
      | 17 -> Interface
      | 18 -> Object (get_struct_pointer x 0)
      | _  -> invalid_msg "invalid Value.unnamed_union_t type tag"
  end

  module Annotation = struct
    type 'cap t = 'cap StructStorage.t option

    let id_get (x : 'cap t) : Uint64.t =
      Util.decode_uint64_le (make_struct_byte_reader x 0 8)

    let value_get (x : 'cap t) : 'cap Value.t =
      match get_struct_pointer x 0 with
      | Some pointer_bytes -> deref_struct_pointer pointer_bytes
      | None -> None
  end

  module Type = struct
    type 'cap t = 'cap StructStorage.t option

    module List = struct
      type 'cap t = 'cap StructStorage.t option

      let elementType_get (x : 'cap t) : 'cap t =
        match get_struct_pointer x 0 with
        | Some pointer_bytes -> deref_struct_pointer pointer_bytes
        | None -> None
    end

    module Enum = struct
      type 'cap t = 'cap StructStorage.t option

      let typeId_get (x : 'cap t) : Uint64.t =
        Util.decode_uint64_le (make_struct_byte_reader x 8 8)
    end

    module Struct = struct
      type 'cap t = 'cap StructStorage.t option

      let typeId_get (x : 'cap t) : Uint64.t =
        Util.decode_uint64_le (make_struct_byte_reader x 8 8)
    end

    module Interface = struct
      type 'cap t = 'cap StructStorage.t option

      let typeId_get (x : 'cap t) : Uint64.t =
        Util.decode_uint64_le (make_struct_byte_reader x 8 8)
    end

    type 'cap unnamed_union_t =
      | Void
      | Bool
      | Int8
      | Int16
      | Int32
      | Int64
      | Uint8
      | Uint16
      | Uint32
      | Uint64
      | Float32
      | Float64
      | Text
      | Data
      | List of 'cap List.t
      | Enum of 'cap Enum.t
      | Struct of 'cap Struct.t
      | Interface of 'cap Interface.t
      | Object

    let unnamed_union_get (x : 'cap t) : 'cap unnamed_union_t =
      let tag = Util.decode_uint16_le (make_struct_byte_reader x 0 2) in
      match tag with
      | 0  -> Void
      | 1  -> Bool
      | 2  -> Int8
      | 3  -> Int16
      | 4  -> Int32
      | 5  -> Int64
      | 6  -> Uint8
      | 7  -> Uint16
      | 8  -> Uint32
      | 9  -> Uint64
      | 10 -> Float32
      | 11 -> Float64
      | 12 -> Text
      | 13 -> Data
      | 14 -> List x
      | 15 -> Enum x
      | 16 -> Struct x
      | 17 -> Interface x
      | 18 -> Object
      | _  -> invalid_msg "invalid Type.unnamed_union_t type tag"
  end

  module Method = struct
    type 'cap t = 'cap StructStorage.t option

    let name_get (x : 'cap t) : string =
      get_struct_text_field x 0

    let codeOrder_get (x : 'cap t) : int =
      Util.decode_uint16_le (make_struct_byte_reader x 0 2)

    let paramStructType_get (x : 'cap t) : Uint64.t =
      Util.decode_uint64_le (make_struct_byte_reader x 8 8)

    let resultStructType_get (x : 'cap t) : Uint64.t =
      Util.decode_uint64_le (make_struct_byte_reader x 16 8)

    let annotations_get (x : 'cap t) : ('cap, 'cap Annotation.t) List.t =
      match get_struct_pointer x 1 with
      | Some slice ->
          begin match deref_list_pointer slice with
          | Some list_storage ->
              Some {
                List.storage  = list_storage;
                List.get_item = fun storage i -> Some (StructList.get storage i);
              }
          | None ->
              None
          end
      | None ->
          None
  end

  module Enumerant = struct
    type 'cap t = 'cap StructStorage.t option

    let name_get (x : 'cap t) : string =
      get_struct_text_field x 0

    let codeOrder_get (x : 'cap t) : int =
      Util.decode_uint16_le (make_struct_byte_reader x 0 2)

    let annotations_get (x : 'cap t) : ('cap, 'cap Annotation.t) List.t =
      match get_struct_pointer x 1 with
      | Some slice ->
          begin match deref_list_pointer slice with
          | Some list_storage ->
              Some {
                List.storage  = list_storage;
                List.get_item = fun storage i -> Some (StructList.get storage i);
              }
          | None ->
              None
          end
      | None ->
          None
  end

  module Field = struct
    type 'cap t = 'cap StructStorage.t option

    module Slot = struct
      type 'cap t = 'cap StructStorage.t option

      let offset_get (x : 'cap t) : Uint32.t =
        Util.decode_uint32_le (make_struct_byte_reader x 4 4)

      let type_get (x : 'cap t) : 'cap Type.t =
        match get_struct_pointer x 2 with
        | Some pointer_bytes -> deref_struct_pointer pointer_bytes
        | None -> None

      let defaultValue_get (x : 'cap t) : 'cap Value.t =
        match get_struct_pointer x 3 with
        | Some pointer_bytes -> deref_struct_pointer pointer_bytes
        | None -> None

      let hadExplicitDefault_get (x : 'cap t) : bool =
        get_struct_bit x 16 0
    end

    module Group = struct
      type 'cap t = 'cap StructStorage.t option

      let typeId_get (x : 'cap t) : Uint64.t =
        Util.decode_uint64_le (make_struct_byte_reader x 16 8)
    end

    type 'cap unnamed_union_t =
        | Slot of 'cap Slot.t
        | Group of 'cap Group.t

    module Ordinal = struct
      type 'cap t = 'cap StructStorage.t option

      type unnamed_union_t =
        | Implicit
        | Explicit of int

      let unnamed_union_get (x : 'cap t) : unnamed_union_t =
        match Util.decode_uint16_le (make_struct_byte_reader x 10 2) with
        | 0 -> Implicit
        | 1 -> Explicit (Util.decode_uint16_le (make_struct_byte_reader x 12 2))
        | _ -> invalid_msg "invalid Field.Ordinal.unnamed_union_t type tag"
    end

    let name_get (x : 'cap t) : string =
      get_struct_text_field x 0

    let codeOrder_get (x : 'cap t) : int =
      Util.decode_uint16_le (make_struct_byte_reader x 0 2)

    let annotations_get (x : 'cap t) : ('cap, 'cap Annotation.t) List.t =
      match get_struct_pointer x 1 with
      | Some slice ->
          begin match deref_list_pointer slice with
          | Some list_storage ->
              Some {
                List.storage  = list_storage;
                List.get_item = fun storage i -> Some (StructList.get storage i);
              }
          | None ->
              None
          end
      | None ->
          None

    let discriminantValue_get (x : 'cap t) : int =
      Util.decode_uint16_le (make_struct_byte_reader x ~default_bytes:[| 0xff; 0xff |] 2 2)

    let unnamed_union_get (x : 'cap t) : 'cap unnamed_union_t =
      match Util.decode_uint16_le (make_struct_byte_reader x 8 2) with
      | 0 -> Slot x
      | 1 -> Group x
      | _ -> invalid_arg "invalid Field.unnamed_union_t type tag"

    let ordinal_get (x : 'cap t) : 'cap Ordinal.t = x
  end

  module Node = struct
    type 'cap t = 'cap StructStorage.t option

    module NestedNode = struct
      type 'cap t = 'cap StructStorage.t option

      let name_get (x : 'cap t) : string =
        get_struct_text_field x 0

      let id_get (x : 'cap t) : Uint64.t =
        Util.decode_uint64_le (make_struct_byte_reader x 0 8)
    end

    module Struct = struct
      type 'cap t = 'cap StructStorage.t option

      let dataWordCount_get (x : 'cap t) : int =
        Util.decode_uint16_le (make_struct_byte_reader x 14 2)

      let pointerCount_get (x : 'cap t) : int =
        Util.decode_uint16_le (make_struct_byte_reader x 24 2)

      let preferredListEncoding_get (x : 'cap t) : ElementSize.t =
        let int_val = Util.decode_uint16_le (make_struct_byte_reader x 26 2) in
        match int_val with
        | 0 -> ElementSize.Empty
        | 1 -> ElementSize.Bit
        | 2 -> ElementSize.Byte
        | 3 -> ElementSize.TwoBytes
        | 4 -> ElementSize.FourBytes
        | 5 -> ElementSize.EightBytes
        | 6 -> ElementSize.Pointer
        | 7 -> ElementSize.InlineComposite
        | _ -> invalid_msg "invalid ElementSize enum value"

      let isGroup_get (x : 'cap t) : bool =
        get_struct_bit x 28 0

      let discriminantCount_get (x : 'cap t) : int =
        Util.decode_uint16_le (make_struct_byte_reader x 30 2)

      let discriminantOffset_get (x : 'cap t) : Uint32.t =
        Util.decode_uint32_le (make_struct_byte_reader x 32 4)

      let fields_get (x : 'cap t) : ('cap, 'cap Field.t) List.t =
        match get_struct_pointer x 3 with
        | Some slice ->
            begin match deref_list_pointer slice with
            | Some list_storage ->
                Some {
                  List.storage  = list_storage;
                  List.get_item = fun storage i -> Some (StructList.get storage i);
                }
            | None ->
                None
            end
        | None ->
            None
    end

    module Enum = struct
      type 'cap t = 'cap StructStorage.t option

      let enumerants_get (x : 'cap t) : ('cap, 'cap Enumerant.t) List.t =
        match get_struct_pointer x 3 with
        | Some slice ->
            begin match deref_list_pointer slice with
            | Some list_storage ->
                Some {
                  List.storage  = list_storage;
                  List.get_item = fun storage i -> Some (StructList.get storage i);
                }
            | None ->
                None
            end
        | None ->
            None
    end

    module Interface = struct
      type 'cap t = 'cap StructStorage.t option

      let methods_get (x : 'cap t) : ('cap, 'cap Method.t) List.t =
        match get_struct_pointer x 3 with
        | Some slice ->
            begin match deref_list_pointer slice with
            | Some list_storage ->
                Some {
                  List.storage  = list_storage;
                  List.get_item = fun storage i -> Some (StructList.get storage i);
                }
            | None ->
                None
            end
        | None ->
            None

      let extends_get (x : 'cap t) : ('cap, Uint64.t) List.t =
        match get_struct_pointer x 4 with
        | Some slice ->
            begin match deref_list_pointer slice with
            | Some list_storage ->
                begin match list_storage.ListStorage.storage_type with
                | ListStorage.Bytes 8 ->
                    Some {
                      List.storage  = list_storage;
                      List.get_item = fun storage i ->
                        Util.decode_uint64_le (Slice.get (BytesList.get storage i));
                    }
                | _ ->
                    invalid_msg "decoded non-bytes pointer where bytes pointer was expected"
                end
            | None ->
                None
            end
        | None ->
            None

    end

    module Const = struct
      type 'cap t = 'cap StructStorage.t option

      let type_get (x : 'cap t) : 'cap Type.t =
        match get_struct_pointer x 3 with
        | Some pointer_bytes -> deref_struct_pointer pointer_bytes
        | None -> None

      let value_get (x : 'cap t) : 'cap Value.t =
        match get_struct_pointer x 4 with
        | Some pointer_bytes -> deref_struct_pointer pointer_bytes
        | None -> None
    end

    module Annotation = struct
      type 'cap t = 'cap StructStorage.t option

      let type_get (x : 'cap t) : 'cap Type.t =
        match get_struct_pointer x 3 with
        | Some pointer_bytes -> deref_struct_pointer pointer_bytes
        | None -> None

      let targetsFile_get (x : 'cap t) : bool =
        get_struct_bit x 14 0

      let targetsConst_get (x : 'cap t) : bool =
        get_struct_bit x 14 1

      let targetsEnum_get (x : 'cap t) : bool =
        get_struct_bit x 14 2

      let targetsEnumerant_get (x : 'cap t) : bool =
        get_struct_bit x 14 3

      let targetStruct_get (x : 'cap t) : bool =
        get_struct_bit x 14 4

      let targetsField_get (x : 'cap t) : bool =
        get_struct_bit x 14 5

      let targetsUnion_get (x : 'cap t) : bool =
        get_struct_bit x 14 6

      let targetsGroup_get (x : 'cap t) : bool =
        get_struct_bit x 14 7

      let targetsInterface_get (x : 'cap t) : bool =
        get_struct_bit x 15 0

      let targetsMethod_get (x : 'cap t) : bool =
        get_struct_bit x 15 1

      let targetsParam_get (x : 'cap t) : bool =
        get_struct_bit x 15 2

      let targetsAnnotation_get (x : 'cap t) : bool =
        get_struct_bit x 15 3
    end

    type 'cap unnamed_union_t =
      | File
      | Struct of 'cap Struct.t
      | Enum of 'cap Enum.t
      | Interface of 'cap Interface.t
      | Const of 'cap Const.t
      | Annotation of 'cap Annotation.t

    let id_get (x : 'cap t) : Uint64.t =
      Util.decode_uint64_le (make_struct_byte_reader x 0 8)

    let displayName_get (x : 'cap t) : string =
      get_struct_text_field x 0

    let displayNamePrefixLength_get (x : 'cap t) : Uint32.t =
      Util.decode_uint32_le (make_struct_byte_reader x 8 4)

    let scopeId_get (x : 'cap t) : Uint64.t =
      Util.decode_uint64_le (make_struct_byte_reader x 8 8)

    let nestedNodes_get (x : 'cap t) : ('cap, 'cap NestedNode.t) List.t =
      match get_struct_pointer x 1 with
      | Some slice ->
          begin match deref_list_pointer slice with
          | Some list_storage ->
              Some {
                List.storage  = list_storage;
                List.get_item = fun storage i -> Some (StructList.get storage i);
              }
          | None ->
              None
          end
      | None ->
          None

    let annotations_get (x : 'cap t) : ('cap, 'cap Annotation.t) List.t =
      match get_struct_pointer x 2 with
      | Some slice ->
          begin match deref_list_pointer slice with
          | Some list_storage ->
              Some {
                List.storage  = list_storage;
                List.get_item = fun storage i -> Some (StructList.get storage i);
              }
          | None ->
              None
          end
      | None ->
          None

    let unnamed_union_get (x : 'cap t) : 'cap unnamed_union_t =
      match Util.decode_uint16_le (make_struct_byte_reader x 12 2) with
      | 0 -> File
      | 1 -> Struct x
      | 2 -> Enum x
      | 3 -> Interface x
      | 4 -> Const x
      | 5 -> Annotation x
      | _ -> invalid_msg "invalid Node.unnamed_union_t type tag"
  end
end
