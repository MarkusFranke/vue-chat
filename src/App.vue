<script setup>
import { ref, onMounted, watch, nextTick, computed } from 'vue';
import { watchEffect } from 'vue';

const messages = ref([]);
const newMessage = ref('');
const conversationId = ref(null);
const threadId = ref(null);
const isLoading = ref(false);
const error = ref(null);
const isTyping = ref(false);
const messageCounter = ref(0);

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
    
    // Add welcome message with unique key
    messages.value.push({
      id: `msg-${messageCounter.value++}`,  // Use .value here
      content: "Hello! How can I help you today?",
      role: 'assistant',
      status: 'complete',  // Add status
      timestamp: Date.now()  // Add timestamp
    });
  } catch (err) {
    error.value = err.message;
  }
}

async function handleStreamResponse(reader) {
  const decoder = new TextDecoder();
  const messageId = `msg-${messageCounter.value++}`;
  
  // Initialize message
  const initialMessage = {
    id: messageId,
    content: '',
    role: 'assistant',
    status: 'pending',
    timestamp: Date.now()
  };
  
  messages.value = [...messages.value, initialMessage];
  const messageIndex = messages.value.length - 1;

  try {
    let buffer = '';
    
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      
      buffer += decoder.decode(value, { stream: true });
      
      while (buffer.includes('\n\n')) {
        const endIndex = buffer.indexOf('\n\n');
        const line = buffer.slice(0, endIndex).trim();
        buffer = buffer.slice(endIndex + 2);
        
        if (line.startsWith('data: ')) {
          try {
            const data = JSON.parse(line.slice(6));
            
            // Create new message object with updated content and status
            const updatedMessage = {
              ...messages.value[messageIndex],
              content: data.content || messages.value[messageIndex].content,
              status: data.status || messages.value[messageIndex].status
            };
            
            // Create new messages array with updated message
            messages.value = [
              ...messages.value.slice(0, messageIndex),
              updatedMessage,
              ...messages.value.slice(messageIndex + 1)
            ];
            
            console.log('Stream update:', {
              messageId,
              content: data.content,
              status: data.status
            });
          } catch (e) {
            console.error('Parse error:', e);
          }
        }
      }
    }
  } catch (err) {
    console.error('Stream error:', err);
    // Update message status to error
    const errorMessage = {
      ...messages.value[messageIndex],
      status: 'error',
      content: 'Error processing message'
    };
    messages.value = [
      ...messages.value.slice(0, messageIndex),
      errorMessage,
      ...messages.value.slice(messageIndex + 1)
    ];
  }
}

watchEffect(() => {
  console.log('Messages updated:', JSON.stringify(messages.value));
});

// Keep the computed for consistent display
const displayMessages = computed(() => {
  return messages.value.map(msg => ({
    ...msg,
    displayContent: msg.content || ''
  }));
});

// Add message sending function
async function sendMessage() {
  if (!newMessage.value.trim() || !conversationId.value) return;
  
  console.log('[Send] Starting message send');
  const messageContent = newMessage.value;
  newMessage.value = '';
  error.value = null;
  
  try {
    // Add user message
    messages.value = [...messages.value, {
      id: `msg-${messageCounter.value++}`,  // Use .value here
      content: messageContent,
      role: 'user',
      status: 'complete',  // Add status
      timestamp: Date.now()  // Add timestamp
    }];

    if (!threadId.value) {
      await createConversation();
    }

    console.log('[Send] Sending fetch request');
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
      throw new Error('Failed to send message');
    }

    const reader = response.body.getReader();
    await handleStreamResponse(reader);
  } catch (err) {
    console.error('[Send] Error:', err);
    error.value = err.message;
  }
}

// Add logging to watch function
watch(messages, (newVal, oldVal) => {
  console.log('[Watch] Messages updated');
  console.log('[Watch] Old value:', oldVal);
  console.log('[Watch] New value:', newVal);
  nextTick(() => {
    const container = document.querySelector('.messages');
    if (container) {
      container.scrollTop = container.scrollHeight;
      console.log('[Watch] Scrolled to bottom');
    }
  });
}, { deep: true });

// Initialize
onMounted(() => {
  createConversation();
});

watch(messages, (newVal) => {
  try {
    console.log('Messages state:', {
      count: newVal.length,
      messages: newVal.map(m => ({
        id: m.id,
        content: m.content?.substring(0, 50),
        status: m.status
      }))
    });
  } catch (err) {
    console.error('Error in messages watch:', err);
  }
}, { deep: true });

</script>

<template>
  <div class="chat-container">
    <div v-if="error" class="error-banner">
      {{ error }}
    </div>
    <div v-else class="chat-interface">
      <div class="messages">
        <TransitionGroup name="fade">
          <div
            v-for="message in messages"
            :key="message.id"
            :class="['message', message.role, message.status]"
          >
            <div class="message-content">
              {{ message.content || '...' }}
            </div>
            <div v-if="message.status === 'pending'" class="typing-indicator">
              <span class="dot"></span>
              <span class="dot"></span>
              <span class="dot"></span>
            </div>
          </div>
        </TransitionGroup>
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
        >
          Send
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
  height: 100vh;
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

.message-content {
  white-space: pre-wrap;
  word-break: break-word;
  min-height: 1em;
}

.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.2s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

/* Add to existing styles */
.message {
  position: relative;
  transition: all 0.2s ease;
}

.debug {
  position: absolute;
  bottom: -12px;
  right: 5px;
  font-size: 8px;
  opacity: 0.5;
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

.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.3s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>