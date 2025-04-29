import express from 'express'
import { Connection, oauth2 } from 'jsforce'
import { storeTokens } from '../models/tokenStore.js'

const router = express.Router()

const oauth2Client = new oauth2({
  loginUrl: 'https://login.salesforce.com',
  clientId: process.env.SF_CLIENT_ID,
  clientSecret: process.env.SF_CLIENT_SECRET,
  redirectUri: process.env.CALLBACK_URL
})

router.get('/init', (req, res) => {
  const url = oauth2Client.getAuthorizationUrl({ scope: 'full refresh_token' })
  res.redirect(url)
})

router.get('/callback', async (req, res) => {
  const conn = new Connection({ oauth2: oauth2Client })
  await conn.authorize(req.query.code)
  await storeTokens(conn.accessToken, conn.refreshToken, conn.instanceUrl)
  res.redirect('/chat.html')
})

export default router
