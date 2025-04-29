import express from 'express'
import bodyParser from 'body-parser'
import cors from 'cors'
import dotenv from 'dotenv'
import oauthRoutes from './routes/oauth.js'
import salesforceRoutes from './routes/salesforce.js'
import chatRoutes from './routes/chat.js'

dotenv.config()

const app = express()
app.use(cors())
app.use(bodyParser.json())

app.use('/oauth', oauthRoutes)
app.use('/api', salesforceRoutes)
app.use('/chat', chatRoutes)

app.listen(process.env.PORT, () => {
  console.log(`Server running on port ${process.env.PORT}`)
})
