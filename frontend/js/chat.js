const chatWindow = document.getElementById('chatWindow')
const userInput = document.getElementById('userInput')
const sendBtn = document.getElementById('sendBtn')

function addMessage(role, text) {
  const msg = document.createElement('div')
  msg.className = role === 'user' ? 'text-right mb-2' : 'text-left mb-2'
  msg.innerHTML = `<span class="inline-block p-2 rounded ${role === 'user' ? 'bg-blue-600 text-white' : 'bg-gray-200'}">${text}</span>`
  chatWindow.appendChild(msg)
  chatWindow.scrollTop = chatWindow.scrollHeight
}

sendBtn.addEventListener('click', async () => {
  const message = userInput.value.trim()
  if (!message) return

  addMessage('user', message)
  userInput.value = ''

  const response = await fetch('/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ message })
  })

  const data = await response.json()
  addMessage('assistant', data.reply || 'Done.')
})
