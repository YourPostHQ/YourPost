// YourPost Webmail - Main Application

const API_BASE = '/api/v1';
let authToken = localStorage.getItem('yourpost_token');
let currentUser = localStorage.getItem('yourpost_user');
let currentFolder = 'INBOX';
let currentMessageId = null;

// Initialize app
document.addEventListener('DOMContentLoaded', () => {
    if (authToken && currentUser) {
        showApp();
    } else {
        showLogin();
    }
    setupEventListeners();
});

function setupEventListeners() {
    // Login form
    document.getElementById('login-form').addEventListener('submit', handleLogin);
    
    // Logout
    document.getElementById('logout-btn').addEventListener('click', handleLogout);
    
    // Folder navigation
    document.querySelectorAll('.folder-item').forEach(item => {
        item.addEventListener('click', (e) => {
            e.preventDefault();
            const folder = item.dataset.folder;
            switchFolder(folder);
        });
    });
    
    // Refresh button
    document.getElementById('refresh-btn').addEventListener('click', () => loadMessages());
    
    // Back button
    document.getElementById('back-btn').addEventListener('click', showMessageList);
    
    // Compose button
    document.getElementById('compose-btn').addEventListener('click', showCompose);
    document.getElementById('close-compose').addEventListener('click', hideCompose);
    document.getElementById('cancel-compose').addEventListener('click', hideCompose);
    document.getElementById('compose-form').addEventListener('submit', handleSend);
    
    // Reply button
    document.getElementById('reply-btn').addEventListener('click', handleReply);
    
    // Delete button
    document.getElementById('delete-btn').addEventListener('click', handleDelete);
}

// Authentication
async function handleLogin(e) {
    e.preventDefault();
    const email = document.getElementById('email').value;
    const password = document.getElementById('password').value;
    const errorDiv = document.getElementById('login-error');
    
    try {
        const response = await fetch(`${API_BASE}/auth`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ email, password })
        });
        
        if (response.ok) {
            const data = await response.json();
            authToken = data.token;
            currentUser = email;
            localStorage.setItem('yourpost_token', authToken);
            localStorage.setItem('yourpost_user', currentUser);
            showApp();
        } else {
            errorDiv.textContent = 'Invalid email or password';
            errorDiv.classList.remove('hidden');
        }
    } catch (error) {
        errorDiv.textContent = 'Connection error. Please try again.';
        errorDiv.classList.remove('hidden');
    }
}

function handleLogout() {
    authToken = null;
    currentUser = null;
    localStorage.removeItem('yourpost_token');
    localStorage.removeItem('yourpost_user');
    showLogin();
}

// Screen management
function showLogin() {
    document.getElementById('login-screen').classList.add('active');
    document.getElementById('app-screen').classList.remove('active');
}

function showApp() {
    document.getElementById('login-screen').classList.remove('active');
    document.getElementById('app-screen').classList.add('active');
    document.getElementById('user-email').textContent = currentUser;
    loadFolders();
    switchFolder('INBOX');
}

// Folder management
async function loadFolders() {
    try {
        const response = await fetch(`${API_BASE}/mailboxes/${currentUser}/folders`, {
            headers: { 'Authorization': `Bearer ${authToken}` }
        });
        if (response.ok) {
            const data = await response.json();
            updateFolderCounts(data.folders);
        }
    } catch (error) {
        console.error('Failed to load folders:', error);
    }
}

function updateFolderCounts(folders) {
    folders.forEach(folder => {
        const item = document.querySelector(`[data-folder="${folder.name}"]`);
        if (item) {
            const badge = item.querySelector('.badge');
            if (badge && folder.unread_count > 0) {
                badge.textContent = folder.unread_count;
                badge.style.display = 'inline';
            }
        }
    });
}

function switchFolder(folderName) {
    currentFolder = folderName;
    currentMessageId = null;
    
    // Update active folder
    document.querySelectorAll('.folder-item').forEach(item => {
        item.classList.toggle('active', item.dataset.folder === folderName);
    });
    
    document.getElementById('current-folder').textContent = folderName;
    showMessageList();
    loadMessages();
}

// Message list
async function loadMessages() {
    const listDiv = document.getElementById('message-list');
    listDiv.innerHTML = '<div class="empty-state"><p>Loading...</p></div>';
    
    try {
        const response = await fetch(`${API_BASE}/mailboxes/${currentUser}/messages?folder=${currentFolder}`, {
            headers: { 'Authorization': `Bearer ${authToken}` }
        });
        
        if (response.ok) {
            const data = await response.json();
            displayMessages(data.messages);
        } else {
            listDiv.innerHTML = '<div class="empty-state"><p>Failed to load messages</p></div>';
        }
    } catch (error) {
        listDiv.innerHTML = '<div class="empty-state"><p>Connection error</p></div>';
    }
}

function displayMessages(messages) {
    const listDiv = document.getElementById('message-list');
    
    if (messages.length === 0) {
        listDiv.innerHTML = '<div class="empty-state"><p>No messages in this folder</p></div>';
        return;
    }
    
    listDiv.innerHTML = messages.map(msg => `
        <div class="message-item ${msg.read ? '' : 'unread'}" data-id="${msg.id}">
            <div class="message-item-header">
                <span class="message-from">${escapeHtml(msg.from)}</span>
                <span class="message-date">${formatDate(msg.date)}</span>
            </div>
            <div class="message-subject">${escapeHtml(msg.subject)}</div>
            <div class="message-preview">${escapeHtml(msg.preview)}</div>
        </div>
    `).join('');
    
    // Add click handlers
    listDiv.querySelectorAll('.message-item').forEach(item => {
        item.addEventListener('click', () => viewMessage(item.dataset.id));
    });
}

// Message view
async function viewMessage(messageId) {
    currentMessageId = messageId;
    
    try {
        const response = await fetch(`${API_BASE}/mailboxes/${currentUser}/messages/${messageId}`, {
            headers: { 'Authorization': `Bearer ${authToken}` }
        });
        
        if (response.ok) {
            const message = await response.json();
            displayMessage(message);
        }
    } catch (error) {
        console.error('Failed to load message:', error);
    }
}

function displayMessage(message) {
    document.getElementById('message-subject').textContent = message.subject;
    document.getElementById('message-from').textContent = `From: ${message.from}`;
    document.getElementById('message-date').textContent = formatDate(message.date);
    document.getElementById('message-body').innerHTML = formatBody(message.body, message.content_type);
    
    document.querySelector('.message-list-container').style.display = 'none';
    document.querySelector('.message-view').classList.remove('hidden');
}

function formatBody(body, contentType) {
    if (contentType === 'text/html') {
        return body;
    }
    // Plain text - escape and convert newlines
    return escapeHtml(body).replace(/\n/g, '<br>');
}

function showMessageList() {
    currentMessageId = null;
    document.querySelector('.message-list-container').style.display = 'flex';
    document.querySelector('.message-view').classList.add('hidden');
}

// Compose
function showCompose() {
    document.getElementById('compose-form').reset();
    document.getElementById('compose-error').classList.add('hidden');
    document.getElementById('compose-modal').classList.remove('hidden');
}

function hideCompose() {
    document.getElementById('compose-modal').classList.add('hidden');
}

async function handleSend(e) {
    e.preventDefault();
    const to = document.getElementById('compose-to').value;
    const subject = document.getElementById('compose-subject').value;
    const body = document.getElementById('compose-body').value;
    const errorDiv = document.getElementById('compose-error');
    
    try {
        const response = await fetch(`${API_BASE}/mailboxes/${currentUser}/send`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${authToken}`
            },
            body: JSON.stringify({ to, subject, body })
        });
        
        if (response.ok) {
            hideCompose();
            switchFolder('Sent');
        } else {
            errorDiv.textContent = 'Failed to send email';
            errorDiv.classList.remove('hidden');
        }
    } catch (error) {
        errorDiv.textContent = 'Connection error. Please try again.';
        errorDiv.classList.remove('hidden');
    }
}

function handleReply() {
    if (!currentMessageId) return;
    
    // Get current message details
    fetch(`${API_BASE}/mailboxes/${currentUser}/messages/${currentMessageId}`, {
        headers: { 'Authorization': `Bearer ${authToken}` }
    }).then(res => res.json()).then(msg => {
        document.getElementById('compose-to').value = msg.from;
        document.getElementById('compose-subject').value = `Re: ${msg.subject}`;
        document.getElementById('compose-body').value = `\n\n---\nOn ${msg.date}, ${msg.from} wrote:\n${msg.body}`;
        showCompose();
    });
}

async function handleDelete() {
    if (!currentMessageId) return;
    
    if (!confirm('Delete this message?')) return;
    
    try {
        const response = await fetch(`${API_BASE}/mailboxes/${currentUser}/messages/${currentMessageId}`, {
            method: 'DELETE',
            headers: { 'Authorization': `Bearer ${authToken}` }
        });
        
        if (response.ok) {
            showMessageList();
            loadMessages();
        }
    } catch (error) {
        console.error('Failed to delete message:', error);
    }
}

// Utility functions
function formatDate(dateStr) {
    const date = new Date(dateStr);
    const now = new Date();
    const isToday = date.toDateString() === now.toDateString();
    
    if (isToday) {
        return date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
    }
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}
