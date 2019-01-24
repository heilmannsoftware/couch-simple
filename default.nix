{ mkDerivation, aeson, attoparsec, base, bifunctors, bytestring
, data-default, exceptions, http-client, http-types, integer-gmp
, mtl, stdenv, text, transformers, unordered-containers, uuid
, vector
}:
mkDerivation {
  pname = "couch-simple";
  version = "0.0.2.0";
  src = ./.;
  libraryHaskellDepends = [
    aeson attoparsec base bifunctors bytestring data-default exceptions
    http-client http-types integer-gmp mtl text transformers
    unordered-containers uuid vector
  ];
  homepage = "https://github.com/mdorman/couch-simple";
  description = "A modern, lightweight, complete client for CouchDB";
  license = stdenv.lib.licenses.mit;
}
