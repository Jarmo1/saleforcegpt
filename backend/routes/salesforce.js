import express from 'express'
import { getConnection } from '../models/tokenStore.js'

const router = express.Router()

router.post('/query', async (req, res) => {
  const conn = await getConnection()
  const result = await conn.query(req.body.soql)
  res.json(result)
})

router.post('/createObject', async (req, res) => {
  const conn = await getConnection()
  const obj = {
    fullName: `${req.body.apiName}__c`,
    label: req.body.label,
    pluralLabel: req.body.pluralLabel,
    nameField: { type: 'Text', label: 'Name' },
    deploymentStatus: 'Deployed',
    sharingModel: 'ReadWrite'
  }
  const result = await conn.metadata.create('CustomObject', obj)
  res.json(result)
})

router.post('/createField', async (req, res) => {
  const conn = await getConnection()
  const fld = {
    fullName: `${req.body.objectApiName}__c.${req.body.fieldApiName}__c`,
    type: req.body.type,
    label: req.body.label,
    length: req.body.length
  }
  const result = await conn.metadata.create('CustomField', fld)
  res.json(result)
})

export default router
