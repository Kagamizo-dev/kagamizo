# Documents from the record: Typst templates (./_templates) over the public
# declarations plus the private values read from Proton Pass at render time.
#
#   legal-documents list                       every entity's documents
#   legal-documents render <entity> <doc> OUT.pdf
#
# `render` runs under `secretspec run --profile legal`, so the EIN, filing
# number and formation facts arrive as environment variables; the renderer
# writes them with the record into one JSON file in a private temporary
# directory, Typst reads it as `sys.inputs.data`, and the directory goes.
# Nothing private is in the Nix store: the templates and the public record
# are, the values never. Rendered documents go to Proton Drive or the
# Matrix room for now (sending mail is a Gap).
#
#   checks.legal-record     Lean proves every record complete for its
#                           status (./_lean/Record.lean), then every template
#                           renders for every entity with placeholder values
{ lib, config, ... }:
let
  top = config;
  records = config.legal.checked;
  inherit (config.identity.checked) entities domains;
  held = config.accounts.held;
  q = builtins.toJSON;

  agentNames = {
    northwest = "Northwest Registered Agent";
  };
  nameOf = e: entities.${e}.legalName;
  controllerOf =
    e:
    if entities.${e}.kind == "person" then
      e
    else
      lib.head (config.governance.controllers.${e} or [ e ]);
  legalEmailOf =
    r:
    let
      withLegal = lib.filter (d: lib.elem "legal" domains.${d}.mailboxes) r.domains;
    in
    if withLegal == [ ] then null else "legal@${lib.head withLegal}";

  # The public part of each record, as the templates read it.
  public = lib.mapAttrs (
    e: r:
    let
      o = r.organization;
      ra = r.registeredAgent;
    in
    {
      entity = e;
      inherit (r)
        legalName
        kind
        status
        purpose
        domains
        ;
      organization =
        if o == null then
          null
        else
          {
            inherit (o) management;
            members = map (m: {
              inherit (m) entity percent;
              name = nameOf m.entity;
            }) o.members;
            managers = map (m: {
              entity = m;
              name = nameOf m;
            }) o.managers;
          };
      formation = {
        inherit (r.formation) state item;
        date = null;
        filingNumber = null;
      };
      ein = {
        inherit (r.ein) item;
        value = null;
      };
      registeredAgent =
        if ra == null then
          null
        else
          {
            account = ra;
            inherit (held.${ra}) provider;
            name = agentNames.${held.${ra}.provider} or held.${ra}.provider;
          };
      inherit (r) addresses taxClassification;
      taxReturnOf = if top.money.tax ? ${e} then top.money.returnOf e else null;
      legalEmail = legalEmailOf r;
      documents = lib.mapAttrsToList (
        _: d:
        {
          inherit (d) kind title issued;
        }
        // d.where
      ) r.documents;
      controller = nameOf (controllerOf e);
      variables = config.legal.variables.${e} or null;
    }
  ) records;

  docsOf =
    r:
    [
      "fact-sheet"
      "kyc-letter"
      "w9-prefill"
    ]
    ++ lib.optional (r.kind != "person") "operating-agreement";
  catalog = lib.mapAttrs (_: r: docsOf r) records;
in
{
  options.legal.public = lib.mkOption {
    type = lib.types.raw;
    readOnly = true;
    default = public;
    description = "Each record as the templates and the homepage read it: public values only.";
  };

  config.perSystem =
    { pkgs, config, ... }:
    let
      templates = lib.fileset.toSource {
        root = ./_templates;
        fileset = lib.fileset.fileFilter (f: f.hasExt "typ") ./_templates;
      };
      recordJson = pkgs.writeText "legal-records.json" (q public);
      catalogJson = q catalog;

      # The renderer proper: the record plus the values in the environment,
      # to one PDF. LEGAL_PLACEHOLDERS=1 marks a render without Proton Pass.
      render = pkgs.writeShellApplication {
        name = "legal-render";
        runtimeInputs = [
          pkgs.typst
          pkgs.jq
          pkgs.coreutils
        ];
        text = ''
          usage="usage: legal-render <entity> <doc> OUT.pdf"
          entity=''${1:?$usage} doc=''${2:?$usage} out=''${3:?$usage}
          catalog=${lib.escapeShellArg catalogJson}
          jq -e --arg e "$entity" --arg d "$doc" '.[$e] // [] | index($d) != null' <<<"$catalog" >/dev/null ||
            { echo "legal-render: no document $doc for $entity; see: legal-documents list" >&2; exit 2; }
          dir=$(mktemp -d)
          chmod 700 "$dir"
          trap 'rm -rf "$dir"' EXIT
          cp -r --no-preserve=mode,ownership ${templates}/. "$dir/t"
          # The values are read from the environment inside jq ($ENV), never
          # placed on a command line. FORMED is "US-XX YYYY-MM-DD"; anything
          # else (the prepared item's hint) counts as not filled yet.
          jq --arg e "$entity" --arg today "$(date -u +%F)" '
            .[$e]
            | (.variables // {}) as $v
            | ($ENV[$v.ein // "-"] // "") as $ein
            | ($ENV[$v.filingNumber // "-"] // "") as $filing
            | ($ENV[$v.formed // "-"] // "") as $formed
            | ($formed | capture("^(?<state>US-[A-Z]{2}) (?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})$")? // null) as $f
            | del(.variables)
            | .rendered = $today
            | .placeholders = (env.LEGAL_PLACEHOLDERS == "1")
            | .ein.value = (if $ein == "" then null else $ein end)
            | .formation.filingNumber = (if $filing == "" then null else $filing end)
            | .formation.date = ($f.date // null)
            | .formation.state = (.formation.state // $f.state // null)
          ' ${recordJson} >"$dir/data.json"
          typst compile --root "$dir" --input data=/data.json "$dir/t/$doc.typ" "$out"
          echo "legal-render: $out ($entity, $doc)" >&2
        '';
      };

      # Lean: the declared records as facts after ./_lean/Record.lean.
      # kebab-case (Nix) to the Lean constructor (camelCase).
      camel =
        s:
        let
          parts = lib.splitString "-" s;
        in
        lib.head parts
        + lib.concatMapStrings (p: lib.toUpper (lib.substring 0 1 p) + lib.substring 1 (-1) p) (
          lib.tail parts
        );
      opt = v: if v == null then "none" else "some ${q v}";
      facts = ''
        namespace Kagamizo.Legal

        /-- Every declared record, rendered by modules/legal/documents.nix. -/
        def records : List Record := [
        ${lib.concatStringsSep ",\n" (
          lib.mapAttrsToList (
            e: r:
            let
              o = r.organization;
            in
            "  { entity := ${q e}, status := .${r.status}, purpose := ${opt r.purpose}, management := ${
                if o == null then "none" else "some .${camel o.management}"
              }, members := [${
                lib.optionalString (o != null) (
                  lib.concatMapStringsSep ", " (
                    m: "{ entity := ${q m.entity}, percent := ${toString m.percent} }"
                  ) o.members
                )
              }], managers := [${
                lib.optionalString (o != null) (lib.concatMapStringsSep ", " q o.managers)
              }], state := ${opt r.formation.state}, formationItem := ${opt r.formation.item}, einItem := ${opt r.ein.item}, registeredAgent := ${opt r.registeredAgent}, documents := [${
                lib.concatStringsSep ", " (
                  lib.mapAttrsToList (
                    _: d: "{ kind := .${camel d.kind}, title := ${q d.title}, issued := ${opt d.issued} }"
                  ) r.documents
                )
              }] }"
          ) records
        )}
        ]

        /-- Every record is complete for its standing. -/
        theorem all_complete : records.all Record.complete = true := by decide +kernel

        end Kagamizo.Legal
      '';
    in
    {
      packages = {
        legal-render = render;
        legal-documents = pkgs.writeShellApplication {
          name = "legal-documents";
          runtimeInputs = [
            config.packages.secretspec
            pkgs.jq
          ];
          text = ''
            export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
            usage="usage: legal-documents list | render <entity> <doc> OUT.pdf"
            catalog=${lib.escapeShellArg catalogJson}
            case "''${1:-}" in
              list)
                jq -r 'to_entries[] | "\(.key): \(.value | join(", "))"' <<<"$catalog"
                ;;
              render)
                entity=''${2:?$usage} doc=''${3:?$usage} out=''${4:?$usage}
                exec secretspec run --file ${config.packages.secretspec-toml} --profile legal \
                  --reason "legal-documents render $entity $doc" -- ${lib.getExe render} "$entity" "$doc" "$out"
                ;;
              *)
                echo "$usage" >&2
                exit 2
                ;;
            esac
          '';
        };
      };

      checks.legal-record =
        pkgs.runCommand "legal-record"
          {
            nativeBuildInputs = [
              pkgs.lean4
              render
              pkgs.jq
            ];
            inherit facts;
            passAsFile = [ "facts" ];
          }
          ''
            cat ${./_lean/Record.lean} "$factsPath" > Check.lean
            lean Check.lean
            # Every template, for every entity, with placeholder values.
            export LEGAL_PLACEHOLDERS=1
            ${lib.concatStrings (
              lib.mapAttrsToList (_: v: ''
                export ${v.ein}=00-0000000 ${v.filingNumber}=0000-000000 ${v.formed}="US-XX 2000-01-01"
              '') top.legal.variables
            )}
            mkdir -p $out
            for pair in $(jq -r 'to_entries[] | .key as $e | .value[] | "\($e)/\(.)"' <<<${lib.escapeShellArg catalogJson}); do
              mkdir -p "$out/''${pair%/*}"
              legal-render "''${pair%/*}" "''${pair#*/}" "$out/$pair.pdf" 2>/dev/null || {
                echo "legal-record: $pair does not render" >&2
                legal-render "''${pair%/*}" "''${pair#*/}" "$out/$pair.pdf"
                exit 1
              }
              test -s "$out/$pair.pdf"
            done
            cp Check.lean $out/
          '';
    };
}
