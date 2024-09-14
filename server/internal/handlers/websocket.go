package handlers

import (
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
	"github.com/mayerstrk/live.nvim/server/internal/utils"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true // Allows all origins, adjust if needed
	},
}

var (
	clients    = make(map[*websocket.Conn]bool)
	clientsMux sync.Mutex
)

// HandleWebSocket manages WebSocket connections and broadcasts updates
func HandleWebSocket(logger *utils.Logger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			logger.Error("WebSocket upgrade error:", err)
			return
		}
		defer conn.Close()

		// Register new client
		clientsMux.Lock()
		clients[conn] = true
		clientsMux.Unlock()

		for {
			// Read message from browser
			_, msg, err := conn.ReadMessage()
			if err != nil {
				logger.Error("Error reading WebSocket message:", err)
				break
			}

			// Broadcast received message (diff) to all clients
			broadcastUpdate(msg, logger)
		}

		// Unregister client on disconnect
		clientsMux.Lock()
		delete(clients, conn)
		clientsMux.Unlock()
	}
}

// broadcastUpdate sends a message to all connected clients
func broadcastUpdate(message []byte, logger *utils.Logger) {
	clientsMux.Lock()
	defer clientsMux.Unlock()

	for client := range clients {
		err := client.WriteMessage(websocket.TextMessage, message)
		if err != nil {
			logger.Error("Error broadcasting message:", err)
			client.Close()
			delete(clients, client)
		}
	}
}
