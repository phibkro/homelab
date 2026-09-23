/**
  Research capability for the operator account.

  The fetcher is placed next to its Paperless consumption sink. This profile
  owns the host-local integration; the resolver implementation remains a
  reusable capability module.
*/
_: {
  imports = [ ../../users/nori/programs/papers-fetch/nixos.nix ];

  nori.papersFetch.email = "philib.krogh@gmail.com";
  services.paperless.consumptionDirIsPublic = true;
}
