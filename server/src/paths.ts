/** The single supported app contract; lower positive versions are retired. */
export const currentApiVersion = 1;

/** Only this version can reach account and ledger services. */
export const apiBasePath = `/api/v${currentApiVersion}`;

/** Better Auth's browser callback lives under the same contract. */
export const authBasePath = `${apiBasePath}/auth`;
