document.getElementById('connectBtn').addEventListener('click', async () => {
  const clientId = document.getElementById('clientId').value.trim()
  const clientSecret = document.getElementById('clientSecret').value.trim()

  if (!clientId || !clientSecret) {
    alert('Please enter both Client ID and Client Secret.')
    return
  }

  try {
    const res = await fetch('/api/store-credentials', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ clientId, clientSecret })
    })

    const result = await res.json()
    if (result.success) {
      window.location.href = '/oauth/init'
    } else {
      alert('Failed to store credentials. Please try again.')
    }
  } catch (err) {
    alert('Error connecting to backend: ' + err.message)
  }
})
