package main

import (
	"fmt"
	"html/template"
	"log"
	"net"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
)

var (
	addr     string
	upgrader = websocket.Upgrader{}
	mu       sync.Mutex
	content  = "" // Stores the full buffer content
)

func main() {
	listener, err := net.Listen("tcp", "localhost:0")
	if err != nil {
		log.Fatalf("Failed to start listener: %v", err)
	}
	defer listener.Close()

	addr = listener.Addr().String()
	fmt.Printf("WebSocket Server Address: ws://%s/ws\n", addr)
	fmt.Printf("HTTP Server Address: http://%s\n", addr)

	http.HandleFunc("/", serveHome)
	http.HandleFunc("/ws", serveWs)

	err = http.Serve(listener, nil)
	if err != nil {
		log.Fatalf("HTTP server error: %v", err)
	}
}

func serveHome(w http.ResponseWriter, r *http.Request) {
	tmpl, err := template.New("home").Parse(homeHTML)
	if err != nil {
		log.Printf("Failed to parse template: %v", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	err = tmpl.Execute(w, nil)
	if err != nil {
		log.Printf("Failed to execute template: %v", err)
	} else {
		log.Println("Home page served successfully")
	}
}

func serveWs(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("Failed to upgrade to WebSocket: %v", err)
		return
	}
	defer conn.Close()
	log.Println("WebSocket connection established")

	// Send the initial full content
	mu.Lock()
	err = conn.WriteMessage(websocket.TextMessage, []byte(content))
	mu.Unlock()
	if err != nil {
		log.Printf("Failed to send initial content: %v", err)
		return
	} else {
		log.Println("Initial content sent successfully")
	}

	// Read updates from the client
	for {
		_, message, err := conn.ReadMessage()
		if err != nil {
			log.Printf("Error reading message: %v", err)
			break
		}

		// Update the content with the received data
		mu.Lock()
		content = string(message) // For simplicity, we replace the content
		mu.Unlock()
		log.Println("Content updated successfully")

		// Broadcast the updated content to the client
		err = conn.WriteMessage(websocket.TextMessage, message)
		if err != nil {
			log.Printf("Failed to send updated content: %v", err)
			break
		} else {
			log.Println("Updated content sent successfully")
		}
	}
}

const homeHTML = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Live.nvim Buffer Content</title>
</head>
<body>
    <h1>Buffer Content:</h1>
    <pre id="content"></pre>

    <script>
        let ws = new WebSocket("ws://{{.}}/ws");

        ws.onmessage = function(event) {
            document.getElementById('content').textContent = event.data;
        };

        ws.onopen = function() {
            console.log("WebSocket connection opened");
        };

        ws.onclose = function() {
            console.log("WebSocket connection closed");
        };

        ws.onerror = function(error) {
            console.error("WebSocket error: " + error);
        };
    </script>
</body>
</html>
`
