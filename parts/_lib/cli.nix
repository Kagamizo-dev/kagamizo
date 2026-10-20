# Typed command lines and OpenTofu configs, checked against ../../catalog.
#
#   cli.cf "accounts tokens create" { name = "x"; policies = [ ... ]; }
#   cli.passCli "vault create" { name = "Kagamizo-CI"; }
#   cli.gh "secret set" { secret-name = "X"; repo = "o/r"; env = "e"; }
#
# return the command as one shell-quoted string. An unknown command, an
# unknown option, a missing required one or a value of the wrong type fails
# evaluation with the command and field named. Values only known when the
# script runs are written { shell = "$domain"; } and spliced in, quoted.
#
#   cli.tofu config
#
# returns an OpenTofu JSON config unchanged when every resource and data
# source exists in the pinned provider, uses only its attributes and sets the
# required ones; `tofu validate` then checks the nesting.
{ lib, fx }:
let
  inherit (fx.types)
    Record
    String
    Bool
    Any
    refined
    ;

  catalog = name: builtins.fromJSON (builtins.readFile ../../catalog/${name}.json);
  cfCatalog = catalog "cf";
  passCatalog = catalog "pass-cli";
  ghCatalog = catalog "gh";
  provider = catalog "cloudflare-provider";

  # A value the shell supplies at run time; the tool checks it then.
  Runtime = Record { shell = String; };
  isRuntime = v: builtins.isAttrs v && v ? shell;
  orRuntime = name: t: refined name Any (v: t.check v || Runtime.check v);

  Number = refined "Number" Any (v: builtins.isInt v || builtins.isFloat v);
  # Strings, or lists and attrsets that go out as JSON (policies, bodies, ...).
  Text = refined "StringOrJson" Any (
    v: builtins.isString v || builtins.isList v || builtins.isAttrs v
  );

  errorsOf =
    type: value:
    (fx.handle {
      handlers = fx.effects.typecheck.collecting;
      state = [ ];
    } (type.validate value)).state;

  fail = what: problems: throw "${what}:\n${lib.concatMapStrings (p: "  - ${p}\n") problems}";

  # Up to five known commands sharing the first word, for the error message.
  suggest =
    commands: command:
    let
      first = lib.head (lib.splitString " " command);
      near = lib.filter (c: lib.hasPrefix first c) (lib.attrNames commands);
    in
    if near == [ ] then "" else "; did you mean: ${lib.concatStringsSep ", " (lib.take 5 near)}";

  # Checks params against one catalog entry: known names, required present,
  # each value of its declared type.
  checkParams =
    {
      what,
      fields,
      required,
      params,
    }:
    let
      unknown = lib.subtractLists (lib.attrNames fields) (lib.attrNames params);
      missing = lib.subtractLists (lib.attrNames params) required;
      typeErrors = map (e: e.message) (
        errorsOf (Record (lib.mapAttrs (n: _: fields.${n}) (removeAttrs params unknown))) (
          removeAttrs params unknown
        )
      );
      problems =
        map (n: "unknown option `${n}`; known: ${lib.concatStringsSep ", " (lib.attrNames fields)}") unknown
        ++ map (n: "missing required `${n}`") missing
        ++ typeErrors;
    in
    if problems == [ ] then params else fail what problems;

  quote = v: if isRuntime v then ''"${v.shell}"'' else lib.escapeShellArg (toString v);
  json = v: if builtins.isString v || isRuntime v then v else builtins.toJSON v;

  cf =
    command: params:
    let
      entry =
        cfCatalog.commands.${command}
          or (throw "cf has no command `${command}`${suggest cfCatalog.commands command}");
      typeOf =
        t:
        {
          string = orRuntime "String" Text;
          boolean = orRuntime "Bool" Bool;
          number = orRuntime "Number" Number;
        }
        .${t};
      fields =
        lib.mapAttrs (_: o: typeOf o.type) entry.options
        // lib.listToAttrs (map (a: lib.nameValuePair a.name (typeOf a.type)) entry.args);
      required =
        lib.attrNames (lib.filterAttrs (_: o: o.required) entry.options)
        ++ map (a: a.name) (lib.filter (a: a.required) entry.args);
      p = checkParams {
        what = "cf ${command}";
        inherit fields required params;
      };
      # A variadic argument takes a list: one word per element.
      positional = lib.concatMap (
        a:
        if !(p ? ${a.name}) then
          [ ]
        else if a.variadic && builtins.isList p.${a.name} then
          map quote p.${a.name}
        else
          [ (quote (json p.${a.name})) ]
      ) entry.args;
      option =
        name: v:
        let
          o = entry.options.${name};
        in
        if o.type == "boolean" && !isRuntime v then
          [ (if v then "--${name}" else "--no-${name}") ]
        # A list of plain strings is a yargs array: --scopes a b c.
        else if builtins.isList v && lib.all builtins.isString v then
          [ "--${name}" ] ++ map quote v
        else
          [
            "--${name}"
            (quote (json v))
          ];
      options = lib.concatLists (lib.mapAttrsToList option (removeAttrs p (map (a: a.name) entry.args)));
    in
    lib.concatStringsSep " " ([ "cf ${command}" ] ++ positional ++ options);

  passCli =
    command: params:
    let
      entry =
        passCatalog.commands.${command}
          or (throw "pass-cli has no command `${command}`${suggest passCatalog.commands command}");
      # An option limited to fixed values (a role, an expiration) takes only those.
      valueType =
        name: o:
        if o ? oneOf then
          orRuntime "OneOf[${lib.concatStringsSep "|" o.oneOf}]" (
            refined "${name}" String (v: builtins.elem v o.oneOf)
          )
        else
          orRuntime "String" String;
      fields =
        lib.mapAttrs (name: o: if o.value then valueType name o else Bool) entry.options
        // lib.listToAttrs (map (a: lib.nameValuePair a.name (orRuntime "String" String)) entry.args);
      required = map (a: a.name) (lib.filter (a: a.required) entry.args);
      p = checkParams {
        what = "pass-cli ${command}";
        inherit fields required params;
      };
      positional = lib.concatMap (a: lib.optional (p ? ${a.name}) (quote p.${a.name})) entry.args;
      option =
        name: v:
        if entry.options.${name}.value then
          [
            "--${name}"
            (quote v)
          ]
        else
          lib.optional v "--${name}";
      options = lib.concatLists (lib.mapAttrsToList option (removeAttrs p (map (a: a.name) entry.args)));
    in
    lib.concatStringsSep " " ([ "pass-cli ${command}" ] ++ positional ++ options);

  gh =
    command: params:
    let
      entry =
        ghCatalog.commands.${command}
          or (throw "gh has no command `${command}`${suggest ghCatalog.commands command}");
      Strings = refined "ListOfString" Any (v: builtins.isList v && lib.all builtins.isString v);
      valueType =
        name: o:
        if o ? oneOf then
          orRuntime "OneOf[${lib.concatStringsSep "|" o.oneOf}]" (
            refined name String (v: builtins.elem v o.oneOf)
          )
        else
          {
            number = orRuntime "Number" Number;
            list = orRuntime "ListOfString" Strings;
          }
          .${o.type or ""} or (orRuntime "String" String);
      fields =
        lib.mapAttrs (name: o: if o.value then valueType name o else Bool) entry.options
        // lib.listToAttrs (
          map (
            a: lib.nameValuePair a.name (if a.variadic then Strings else orRuntime "String" String)
          ) entry.args
        );
      required = map (a: a.name) (lib.filter (a: a.required) entry.args);
      p = checkParams {
        what = "gh ${command}";
        inherit fields required params;
      };
      positional = lib.concatMap (
        a:
        if !(p ? ${a.name}) then
          [ ]
        else if builtins.isList p.${a.name} then
          map quote p.${a.name}
        else
          [ (quote p.${a.name}) ]
      ) entry.args;
      option =
        name: v:
        if !entry.options.${name}.value then
          lib.optional v "--${name}"
        # cobra string slices take one comma-separated value.
        else if builtins.isList v then
          [
            "--${name}"
            (quote (lib.concatStringsSep "," v))
          ]
        else
          [
            "--${name}"
            (quote v)
          ];
      options = lib.concatLists (lib.mapAttrsToList option (removeAttrs p (map (a: a.name) entry.args)));
    in
    lib.concatStringsSep " " ([ "gh ${command}" ] ++ positional ++ options);

  # Arguments every resource takes besides its schema's.
  meta = [
    "count"
    "for_each"
    "depends_on"
    "lifecycle"
    "provider"
  ];

  tofu =
    config:
    let
      check =
        kind: schemas: type: name: body:
        let
          what = "${kind}.${type}.${name}";
          schema = schemas.${type} or null;
          settable = lib.filterAttrs (_: a: a.required || a.optional) schema;
          unknown = lib.subtractLists (lib.attrNames settable ++ meta) (lib.attrNames body);
          missing = lib.subtractLists (lib.attrNames body) (
            lib.attrNames (lib.filterAttrs (_: a: a.required) schema)
          );
        in
        if schema == null then
          [ "${what}: the provider has no ${kind} `${type}`" ]
        else
          map (a: "${what}: unknown attribute `${a}`") unknown
          ++ map (a: "${what}: missing required attribute `${a}`") missing;
      inBlock =
        kind: schemas:
        lib.concatLists (
          lib.concatLists (
            lib.mapAttrsToList (type: lib.mapAttrsToList (check kind schemas type)) (config.${kind} or { })
          )
        );
      problems = inBlock "resource" provider.resources ++ inBlock "data" provider.data;
    in
    if problems == [ ] then config else fail "OpenTofu config does not match the provider" problems;
in
{
  inherit
    cf
    passCli
    gh
    tofu
    ;
  # The values a gh option is limited to, e.g. `repo edit` visibilities.
  ghChoices =
    command: option:
    ghCatalog.commands.${command}.options.${option}.oneOf
      or (throw "gh ${command} --${option} takes no fixed set of values");
  # The values a pass-cli option is limited to, e.g. the roles of
  # `agent access grant`, to type declarations with before anything runs.
  passCliChoices =
    command: option:
    passCatalog.commands.${command}.options.${option}.oneOf
      or (throw "pass-cli ${command} --${option} takes no fixed set of values");
  # The OAuth scopes cf's client may request.
  Scope = refined "CfOAuthScope" String (s: builtins.elem s cfCatalog.oauthScopes);
}
