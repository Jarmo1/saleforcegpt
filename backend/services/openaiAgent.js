import OpenAI from 'openai'
import { getTokens } from '../models/tokenStore.js'

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY })

export async function runAgent(userMessage) {
  const tokens = await getTokens()

  const functions = [
    {
      name: 'querySalesforce',
      description: 'Run SOQL queries',
      parameters: {
        type: 'object',
        properties: {
          soql: { type: 'string' }
        },
        required: ['soql']
      }
    },
    {
      name: 'createCustomObject',
      description: 'Create a custom object',
      parameters: {
        type: 'object',
        properties: {
          apiName: { type: 'string' },
          label: { type: 'string' },
          pluralLabel: { type: 'string' }
        },
        required: ['apiName', 'label', 'pluralLabel']
      }
    },
    {
      name: 'createCustomField',
      description: 'Create a custom field',
      parameters: {
        type: 'object',
        properties: {
          objectApiName: { type: 'string' },
          fieldApiName: { type: 'string' },
          type: { type: 'string' },
          label: { type: 'string' },
          length: { type: 'integer' }
        },
        required: ['objectApiName', 'fieldApiName', 'type', 'label']
      }
    }
  ]

  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [{ role: 'user', content: userMessage }],
    functions
  })

  const call = response.choices[0].message.function_call
  const functionName = call.name
  const args = JSON.parse(call.arguments)

  // Add the Salesforce tokens
  const completeArgs = { ...tokens, ...args }

  const res = await fetch(`https://yourdomain.com/api/${functionName}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(completeArgs)
  })

  return await res.json()
}
