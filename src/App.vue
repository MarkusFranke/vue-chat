<script setup>
import { ref, onMounted, watch, nextTick } from 'vue';

const messages = ref([]);
const newMessage = ref('');
const currentConversation = ref(null);
const isLoading = ref(false);
const error = ref(null);
const isTyping = ref(false);
const reconnectAttempts = ref(0);
const MAX_RECONNECTS = 3;

// Generate a random visitor ID that persists for the session
const VISITOR_ID = ref(localStorage.getItem('visitorId') || Math.random().toString(36).substring(7));
localStorage.setItem('visitorId', VISITOR_ID.value);

const API_KEY = APP_PROPS.VITE_API_KEY;
const API_BASE = APP_PROPS.VITE_API_BASE || 'http://localhost:8000/api/v1';

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
    const response = await fetch(`${API_BASE}/assistants/`, {
      method: 'POST',
      headers: {
        'Authorization': `ApiKey ${API_KEY}`,
        'X-Visitor-ID': VISITOR_ID.value,
        'Content-Type': 'application/json'
      }
    });

    if (!response.ok) throw new Error('Failed to create conversation');
    
    const data = await response.json();
    currentConversation.value = data.id;
    
    // Add welcome message
    messages.value.push({
      content: "Hello! How can I help you today?",
      role: 'assistant'
    });
  } catch (error) {
    handleError('Failed to start conversation', error);
  }
}

async function sendMessage() {
  if (!newMessage.value.trim() || !currentConversation.value) return;
  
  const messageContent = newMessage.value;
  newMessage.value = '';
  error.value = null;

  try {
    isLoading.value = true;
    isTyping.value = true;
    
    messages.value.push({
      content: messageContent,
      role: 'user'
    });

    const response = await fetch(
      `${API_BASE}/assistants/${currentConversation.value}/send-message/`,
      {
        method: 'POST',
        headers: {
          'Authorization': `ApiKey ${API_KEY}`,
          'X-Visitor-ID': VISITOR_ID.value,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          message: messageContent
        })
      }
    );

    if (!response.ok) {
      if (response.status === 429) {
        const data = await response.json();
        throw new Error(`Rate limit exceeded. Please try again in ${data.retry_after} seconds.`);
      }
      throw new Error('Failed to send message');
    }

    const reader = response.body.getReader();
    let assistantMessage = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      const chunk = new TextDecoder().decode(value);
      const lines = chunk.split('\n');

      for (const line of lines) {
        if (line.startsWith('data: ')) {
          try {
            const data = JSON.parse(line.slice(6));
            if (data.content) {
              assistantMessage = data.content;
            } else if (data.error) {
              throw new Error(data.error);
            }
          } catch (e) {
            console.error('Error parsing SSE data:', e);
          }
        }
      }
    }

    if (assistantMessage) {
      messages.value.push({
        content: assistantMessage,
        role: 'assistant'
      });
    }

  } catch (error) {
    handleError('Message sending failed', error);
    
    // Try to recreate conversation if it's expired
    if (error.message.includes('expired')) {
      await reconnect();
    }
  } finally {
    isLoading.value = false;
    isTyping.value = false;
  }
}

async function reconnect() {
  if (reconnectAttempts.value >= MAX_RECONNECTS) {
    error.value = 'Maximum reconnection attempts reached. Please refresh the page.';
    return;
  }
  
  reconnectAttempts.value++;
  await createConversation();
}

function handleError(context, error) {
  console.error(`${context}:`, error);
  messages.value.push({
    content: error.message || 'An error occurred. Please try again.',
    role: 'error'
  });
  error.value = error.message;
}

// Initialize
onMounted(() => {
  createConversation();
});
</script>

<template>
  <div class="chat-container">
    <div class="chat-interface">
      <div v-if="error" class="error-banner">
        {{ error }}
      </div>
      
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
          placeholder="Type your message..."
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
/* Previous styles remain the same */

.error-banner {
  background-color: #dc3545;
  color: white;
  padding: 10px;
  border-radius: 4px;
  margin-bottom: 10px;
  text-align: center;
}

.typing {
  display: flex;
  align-items: center;
  gap: 4px;
}

.dot {
  width: 8px;
  height: 8px;
  background: #007bff;
  border-radius: 50%;
  animation: bounce 1.4s infinite ease-in-out;
  display: inline-block;
}

.dot:nth-child(1) { animation-delay: -0.32s; }
.dot:nth-child(2) { animation-delay: -0.16s; }

@keyframes bounce {
  0%, 80%, 100% { transform: scale(0); }
  40% { transform: scale(1.0); }
}

.button.loading {
  position: relative;
  color: transparent;
}

.button.loading::after {
  content: "";
  position: absolute;
  width: 16px;
  height: 16px;
  border: 2px solid transparent;
  border-top-color: white;
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}
</style>