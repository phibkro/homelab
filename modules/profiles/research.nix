/**
  Research capability for the operator account.

  The fetcher is placed next to its Paperless consumption sink. This profile
  owns the host-local integration; the resolver implementation remains a
  reusable capability module.
*/
_: {
  imports = [ ../capabilities/research/papers-fetch ];

  nori.papersFetch.email = "philib.krogh@gmail.com";
  services.paperless.consumptionDirIsPublic = true;
}
