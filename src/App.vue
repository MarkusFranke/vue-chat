<script setup>
import { ref, onMounted, watch, nextTick } from 'vue';

const messages = ref([]);
const newMessage = ref('');
const conversationId = ref(null);
const threadId = ref(null);
const isLoading = ref(false);
const error = ref(null);
const isTyping = ref(false);

// Access environment variables safely
const api_key = import.meta.env.VITE_API_KEY;
const api_base = import.meta.env.VITE_API_BASE || 'http://localhost:8000/api/v1';

// Auto-scroll messages
watch(messages, async () => {
  await nextTick();
  const container = document.querySelector('.messages');
  if (container) {
    container.scrollTop = container.scrollHeight;
  }
}, { deep: true });

async function createConversation() {
  try {
    const response = await fetch(`${api_base}/assistants/`, {
      method: 'POST',
      headers: {
        'Authorization': `ApiKey ${api_key}`,
        'Content-Type': 'application/json'
      }
    });
    
    if (!response.ok) {
      throw new Error('Invalid API key configuration. Please check your .env file.');
    }
    
    const data = await response.json();
    conversationId.value = data.id;
    threadId.value = data.thread_id;
    
    // Add welcome message
    messages.value.push({
      content: "Hello! How can I help you today?",
      role: 'assistant'
    });
  } catch (err) {
    error.value = err.message;
  }
}

async function handleStreamResponse(reader) {
  const decoder = new TextDecoder();
  let buffer = '';
  
  const lastMessageIndex = messages.value.findLastIndex(msg => msg.role === 'assistant');
  if (lastMessageIndex === -1) {
    messages.value.push({ content: '', role: 'assistant' });
  }

  while (true) {
    const { done, value } = await reader.read();
    
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    
    const lines = buffer.split('\n\n');
    buffer = lines.pop(); // Keep any incomplete line in buffer
    
    for (const line of lines) {
      if (line.startsWith('data: ')) {
        try {
          const rawData = line.slice(6).trim();
          const parsed = JSON.parse(rawData);
          
          console.log('Received data:', parsed);
          
          if (parsed.content) {
            const lastMessageIndex = messages.value.findLastIndex(msg => msg.role === 'assistant');
            
            if (lastMessageIndex !== -1) {
              messages.value[lastMessageIndex].content = parsed.content;
            }
          }
          
          if (parsed.error) {
            error.value = parsed.error;
            break;
          }
        } catch (e) {
          console.error('Parsing error:', e);
        }
      }
    }
  }

  isTyping.value = false;
}

function updateAssistantMessage(newContent) {
  // Find last assistant message or create new
  const lastMessageIndex = messages.value.findLastIndex(msg => msg.role === 'assistant');
  
  if (lastMessageIndex === -1 || messages.value[lastMessageIndex].role !== 'assistant') {
    messages.value.push({ content: newContent, role: 'assistant' });
  } else {
    messages.value[lastMessageIndex].content += newContent;
  }
}

async function sendMessage() {
  if (!newMessage.value.trim() || !conversationId.value) return;
  
  const messageContent = newMessage.value;
  newMessage.value = '';
  error.value = null;
  isTyping.value = true;  // Set typing indicator before sending

  try {
    messages.value.push({ content: messageContent, role: 'user' });

    if (!threadId.value) {
      await createConversation();
    }

    const response = await fetch(
      `${api_base}/assistants/${conversationId.value}/send_message/`, 
      {
        method: 'POST',
        headers: {
          'Authorization': `ApiKey ${api_key}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ message: messageContent })
      }
    );

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Failed to send message: ${errorText}`);
    }

    const reader = response.body.getReader();
    await handleStreamResponse(reader);
    
  } catch (err) {
    console.error('Error in sendMessage:', err);
    error.value = err.message;
  } finally {
    isLoading.value = false;
    isTyping.value = false;  // Ensure typing indicator is turned off
  }
}

// Initialize
onMounted(() => {
  createConversation();
});
</script>

<template>
  <div class="chat-container">
    <div v-if="error" class="error-banner">
      {{ error }}
    </div>
    <div v-else class="chat-interface">
      <div class="messages" ref="messageContainer">
        <div
          v-for="(message, index) in messages"
          :key="index"
          :class="['message', message.role]"
        >
          {{ message.content }}
        </div>
        <div v-if="isTyping" class="message assistant typing">
          <span class="dot"></span>
          <span class="dot"></span>
          <span class="dot"></span>
        </div>
      </div>
      <div class="input-area">
        <input
          v-model="newMessage"
          type="text"
          placeholder="Type a message..."
          @keyup.enter="sendMessage"
          :disabled="isLoading"
        >
        <button
          @click="sendMessage"
          :disabled="isLoading || !newMessage.trim()"
          :class="{ loading: isLoading }"
        >
          {{ isLoading ? '...' : 'Send' }}
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.chat-container {
  max-width: 800px;
  margin: 0 auto;
  padding: 20px;
  height: calc(100vh - 100px);
  min-height: 600px;
  display: flex;
  flex-direction: column;
}

.chat-interface {
  flex: 1;
  display: flex;
  flex-direction: column;
  border: 1px solid #ddd;
  border-radius: 8px;
  background: white;
  overflow: hidden;
}

.error-banner {
  background-color: #dc3545;
  color: white;
  padding: 20px;
  border-radius: 8px;
  text-align: center;
  margin-top: 20px;
}

.messages {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.message {
  max-width: 80%;
  padding: 10px 15px;
  border-radius: 15px;
  margin: 5px 0;
}

.user {
  background-color: #007bff;
  color: white;
  align-self: flex-end;
}

.assistant {
  background-color: #f1f1f1;
  color: black;
  align-self: flex-start;
}

.input-area {
  display: flex;
  gap: 10px;
  padding: 20px;
  border-top: 1px solid #ddd;
}

input {
  flex: 1;
  padding: 10px;
  border: 1px solid #ddd;
  border-radius: 4px;
  font-size: 14px;
}

button {
  padding: 10px 20px;
  background-color: #007bff;
  color: white;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  min-width: 80px;
}

button:disabled {
  background-color: #ccc;
  cursor: not-allowed;
}

.typing {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 10px 15px;
}

.dot {
  width: 8px;
  height: 8px;
  background: #777;
  border-radius: 50%;
  animation: bounce 1.4s infinite ease-in-out;
  display: inline-block;
  opacity: 0.5;
}

.dot:nth-child(1) { animation-delay: -0.32s; }
.dot:nth-child(2) { animation-delay: -0.16s; }

@keyframes bounce {
  0%, 80%, 100% { transform: scale(0); }
  40% { transform: scale(1.0); }
}

button.loading {
  position: relative;
  color: transparent;
}

button.loading::after {
  content: "";
  position: absolute;
  width: 16px;
  height: 16px;
  top: 50%;
  left: 50%;
  margin-top: -8px;
  margin-left: -8px;
  border: 2px solid transparent;
  border-top-color: white;
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}
</style>