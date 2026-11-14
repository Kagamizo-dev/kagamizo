# Stripe's API as its pinned OpenAPI spec states it (the stripe-openapi
# flake input, openapi/spec3.json), read in Nix: every operation with its
# path and query parameters and its form-encoded body fields, and every
# object with its fields. A schema is written as a short type string:
#
#   string, integer, boolean, number   the JSON type
#   ref:<schema>                       another object in `objects`
#   array<t>, object, object:<title>   containers (a titled inline object)
#   a|b                                one of several (anyOf)
#   ...|null                           nullable
#
# Enums are listed beside the type. The objects of Financial Connections
# (financial_connections.*, bank_connections_resource_*) keep their
# descriptions, since the bank reads through them; the rest keep types only.
{
  lib,
  spec,
  rev,
  date,
}:
let
  inherit (lib)
    concatStringsSep
    hasPrefix
    last
    mapAttrs
    splitString
    unique
    filterAttrs
    ;
  described = n: hasPrefix "financial_connections" n || hasPrefix "bank_connections_resource" n;

  typeOf =
    s:
    let
      base =
        if s ? "$ref" then
          "ref:${last (splitString "/" s."$ref")}"
        else if s ? anyOf then
          concatStringsSep "|" (unique (map typeOf s.anyOf))
        else if (s.type or null) == "array" then
          "array<${typeOf (s.items or { })}>"
        else if (s.type or null) == "object" then
          (if s ? title then "object:${s.title}" else "object")
        else
          s.type or "any";
    in
    if s.nullable or false then "${base}|null" else base;

  enumOf =
    s:
    s.enum or (
      if (s.type or null) == "array" && (s.items or { }) ? enum then
        s.items.enum
      else if s ? anyOf && lib.any (x: x ? enum) s.anyOf then
        lib.concatMap (x: x.enum or [ ]) s.anyOf
      else
        null
    );

  field =
    withDescription: required: n: s:
    {
      type = typeOf s;
      enum = enumOf s;
      required = lib.elem n required;
      deprecated = s.deprecated or false;
      # An inline object's own fields (a titled params object, say).
      fields =
        if s ? properties then mapAttrs (field withDescription (s.required or [ ])) s.properties else null;
    }
    // lib.optionalAttrs withDescription { description = s.description or null; };

  formBody =
    op:
    let
      body = op.requestBody.content."application/x-www-form-urlencoded".schema or { };
    in
    mapAttrs (field false (body.required or [ ])) (body.properties or { });

  operation = path: method: op: {
    inherit path;
    method = lib.toUpper method;
    summary = op.summary or null;
    description = op.description or null;
    deprecated = op.deprecated or false;
    parameters = builtins.listToAttrs (
      map (p: {
        inherit (p) name;
        value = field false [ ] p.name (p.schema or { }) // {
          "in" = p."in";
          required = p.required or false;
        };
      }) (op.parameters or [ ])
    );
    body = formBody op;
    returns = typeOf (op.responses."200".content."application/json".schema or { });
  };

  operations = builtins.listToAttrs (
    lib.concatLists (
      lib.mapAttrsToList (
        path: methods:
        lib.mapAttrsToList (method: op: {
          name = op.operationId;
          value = operation path method op;
        }) (filterAttrs (m: _: m != "parameters") methods)
      ) spec.paths
    )
  );

  objects = mapAttrs (n: s: {
    description = if described n then s.description or null else null;
    resource = s."x-resourceId" or null;
    fields = mapAttrs (field (described n) (s.required or [ ])) (s.properties or { });
  }) spec.components.schemas;
in
{
  api = {
    title = spec.info.title;
    version = spec.info.version;
    servers = map (s: s.url) spec.servers;
    security = mapAttrs (_: s: { inherit (s) type scheme; }) spec.components.securitySchemes;
    spec = {
      inherit rev date;
      file = "openapi/spec3.json";
      repo = "github.com/stripe/openapi";
    };
  };
  inherit operations objects;
}
