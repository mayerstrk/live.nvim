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
	port      = flag.Int("port", 8080, "port to serve on")
	upgrader  = websocket.Upgrader{}
	clients   = make(map[*websocket.Conn]bool)
	broadcast = make(chan string)
	mutex     = &sync.Mutex{}
)

func main() {
	flag.Parse()

	// _______
	// operation: Starting Go server

	fs := http.FileServer(http.Dir("./static"))
	http.Handle("/", fs)
	http.HandleFunc("/ws", handleConnections)

	go handleMessages()

	addr := fmt.Sprintf(":%d", *port)
	log.Printf("Starting server on %s", addr)
	err := http.ListenAndServe(addr, nil)
	if err != nil {
		log.Fatalf("ListenAndServe: %v", err)
	}

	// end of operation: Starting Go server
	// _______
}

func handleConnections(w http.ResponseWriter, r *http.Request) {
	// _______
	// operation: Handling WebSocket connection

	upgrader.CheckOrigin = func(r *http.Request) bool { return true }
	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("Upgrade error: %v", err)
		return
	}
	defer ws.Close()

	mutex.Lock()
	clients[ws] = true
	mutex.Unlock()

	for {
		_, message, err := ws.ReadMessage()
		if err != nil {
			log.Printf("ReadMessage error: %v", err)
			mutex.Lock()
			delete(clients, ws)
			mutex.Unlock()
			break
		}
		broadcast <- string(message)
	}

	// end of operation: Handling WebSocket connection
	// _______
}

func handleMessages() {
	for {
		// _______
		// operation: Broadcasting messages

		msg := <-broadcast
		mutex.Lock()
		for client := range clients {
			err := client.WriteMessage(websocket.TextMessage, []byte(msg))
			if err != nil {
				log.Printf("WriteMessage error: %v", err)
				client.Close()
				delete(clients, client)
			} else {
				log.Printf("Message broadcasted to client.")
			}
		}
		mutex.Unlock()

		// end of operation: Broadcasting messages
		// _______
	}
}
