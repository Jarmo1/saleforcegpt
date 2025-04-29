let tokens = {}

export async function storeTokens(accessToken, refreshToken, instanceUrl) {
  tokens = { accessToken, refreshToken, instanceUrl }
}

export async function getConnection() {
  const { Connection } = await import('jsforce')
  return new Connection({
    accessToken: tokens.accessToken,
    instanceUrl: tokens.instanceUrl,
    refreshToken: tokens.refreshToken
  })
}

export async function getTokens() {
  return tokens
}
