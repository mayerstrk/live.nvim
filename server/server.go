package main

import (
	"embed"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"

	"github.com/gorilla/websocket"
)

//go:embed web/*
var webFiles embed.FS

var upgrader = websocket.Upgrader{}

var (
	contentMutex sync.Mutex
	content      = make(map[string]string) // Map endpoint to content
)

func main() {
	// _______
	// operation: Start Go server
	// _______

	port := flag.String("port", "0", "server port")
	flag.Parse()

	listener, err := net.Listen("tcp", ":"+*port)
	if err != nil {
		log.Fatalf("Failed to listen on port %s: %v", *port, err)
	}
	defer listener.Close()

	actualPort := listener.Addr().(*net.TCPAddr).Port
	fmt.Printf("Server started on port %d\n", actualPort)

	http.HandleFunc("/code", handleWebSocket)
	http.HandleFunc("/markdown", handleWebSocket)
	http.HandleFunc("/", serveWeb)

	server := &http.Server{}

	go func() {
		if err := server.Serve(listener); err != nil && err != http.ErrServerClosed {
			log.Fatalf("HTTP server error: %v", err)
		}
	}()

	waitForShutdown(server)

	// end of operation: Start Go server
	// _______
}

func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	// _______
	// operation: Handle WebSocket connection
	// _______

	upgrader.CheckOrigin = func(r *http.Request) bool {
		// Allow all origins for local development
		return true
	}

	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("Failed to upgrade connection: %v", err)
		return
	}
	defer func() {
		err := ws.Close()
		if err != nil {
			log.Printf("Failed to close WebSocket: %v", err)
		}
	}()

	endpoint := r.URL.Path
	log.Printf("Client connected to %s", endpoint)

	for {
		messageType, msg, err := ws.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("WebSocket error: %v", err)
			} else {
				log.Printf("Client disconnected from %s: %v", endpoint, err)
			}
			break
		}

		err = processMessage(endpoint, msg)
		if err != nil {
			log.Printf("Failed to process message: %v", err)
			ws.WriteMessage(websocket.TextMessage, []byte("Error processing message"))
			continue
		}

		broadcastContent(ws, messageType, endpoint)
	}

	log.Printf("Connection to %s closed", endpoint)

	// end of operation: Handle WebSocket connection
	// _______
}

func serveWeb(w http.ResponseWriter, r *http.Request) {
	// _______
	// operation: Serve web content
	// _______

	http.FileServer(http.FS(webFiles)).ServeHTTP(w, r)

	// end of operation: Serve web content
	// _______
}

func processMessage(endpoint string, msg []byte) error {
	// _______
	// operation: Process received message
	// _______

	contentMutex.Lock()
	defer contentMutex.Unlock()

	// For this example, we replace the content entirely
	content[endpoint] = string(msg)
	log.Printf("Updated content for %s", endpoint)

	// end of operation: Process received message
	// _______

	return nil
}

func broadcastContent(ws *websocket.Conn, messageType int, endpoint string) {
	// _______
	// operation: Broadcast content to client
	// _______

	contentMutex.Lock()
	data := content[endpoint]
	contentMutex.Unlock()

	err := ws.WriteMessage(messageType, []byte(data))
	if err != nil {
		log.Printf("Failed to send content: %v", err)
	}

	// end of operation: Broadcast content to client
	// _______
}

func waitForShutdown(server *http.Server) {
	// _______
	// operation: Wait for server shutdown
	// _______

	stopChan := make(chan os.Signal, 1)
	signal.Notify(stopChan, os.Interrupt, syscall.SIGTERM)

	<-stopChan
	log.Println("Shutdown signal received")

	if err := server.Close(); err != nil {
		log.Fatalf("Server close failed: %v", err)
	}

	log.Println("Server gracefully stopped")

	// end of operation: Wait for server shutdown
	// _______
}
