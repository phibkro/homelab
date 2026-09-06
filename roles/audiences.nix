let
  definitions = {
    public = {
      visibleTo = [
        "public"
        "family"
        "operator"
      ];
      registrationRequired = false;
    };
    family = {
      visibleTo = [
        "family"
        "operator"
      ];
      registrationRequired = true;
    };
    operator = {
      visibleTo = [ "operator" ];
      registrationRequired = true;
    };
  };
  keys = builtins.attrNames definitions;
in
{
  inherit definitions keys;
  visibleToFor = audience: definitions.${audience}.visibleTo;
  registrationRequired = audience: definitions.${audience}.registrationRequired;
}
