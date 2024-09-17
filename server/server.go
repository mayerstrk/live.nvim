// server.go
package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
)

var (
	addr     = flag.String("addr", "localhost", "http service address")
	port     = flag.String("port", "8080", "port number")
	upgrader = websocket.Upgrader{}
	content  = struct {
		sync.RWMutex
		data string
	}{}
)

func main() {
	flag.Parse()

	http.HandleFunc("/markdown", handleWebSocket)
	http.HandleFunc("/code", handleWebSocket)
	http.HandleFunc("/", serveHome)

	serverAddress := fmt.Sprintf("%s:%s", *addr, *port)
	log.Printf("Server starting on http://%s", serverAddress)

	err := http.ListenAndServe(serverAddress, nil)
	if err != nil {
		log.Fatal("ListenAndServe error:", err)
	}
}

func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("Upgrade error:", err)
		return
	}
	defer conn.Close()

	for {
		_, message, err := conn.ReadMessage()
		if err != nil {
			log.Println("Read error:", err)
			break
		}

		// Operation: Update Content
		content.Lock()
		content.data = applyDiff(content.data, string(message))
		content.Unlock()
		// End of operation: Update Content

		// Broadcast the updated content to all clients if needed
	}
}

func serveHome(w http.ResponseWriter, r *http.Request) {
	http.ServeFile(w, r, "index.html")
}

func applyDiff(oldContent, diff string) string {
	// Implement the Myers diff application here
	// For simplicity, we'll assume the diff is the new content
	return diff
}
