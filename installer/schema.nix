{
  lib,
  systemOptions,
  homeOptions,
  homeDefaults,
}: let
  collect = scope: path: value:
    if lib.isOption value
    then let
      type = value.type.name;
      supported = type == "bool" || type == "str" || (type == "listOf" && value.type.nestedTypes.elemType.name == "str");
      attempt =
        if supported
        then builtins.tryEval (builtins.deepSeq (value.default or null) (value.default or null))
        else {success = false;};
    in [
      {
        inherit scope path type supported;
        description =
          if builtins.isString (value.description or "")
          then value.description or ""
          else "See module documentation";
        writable = !(value.readOnly or false) && !(value.internal or false) && (value.visible or true) != false;
        default =
          if attempt.success
          then attempt.value
          else null;
        presetDefault =
          if scope == "home" && supported
          then lib.attrByPath path null homeDefaults
          else
            (
              if attempt.success
              then attempt.value
              else null
            );
      }
    ]
    else lib.concatLists (lib.mapAttrsToList (name: child: collect scope (path ++ [name]) child) value);
in
  (collect "system" ["my"] systemOptions) ++ (collect "home" ["my"] homeOptions)
