package server

import (
	"fmt"
	"html/template"
	"net"
	"net/http"

	"github.com/yourusername/live.nvim/server/internal/handlers"
	"github.com/yourusername/live.nvim/server/internal/utils"
)

type Server struct {
	port     int
	listener net.Listener
	logger   *utils.Logger
}

func New(logger *utils.Logger) *Server {
	return &Server{
		logger: logger,
	}
}

func (s *Server) Start() error {
	http.HandleFunc("/markdown", handlers.HandleWebSocket(s.logger))
	http.HandleFunc("/code", handlers.HandleWebSocket(s.logger))
	http.HandleFunc("/", s.handleIndex)

	fs := http.FileServer(http.Dir("web/static"))
	http.Handle("/static/", http.StripPrefix("/static/", fs))

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return fmt.Errorf("failed to start server: %w", err)
	}
	s.listener = listener
	s.port = listener.Addr().(*net.TCPAddr).Port

	s.logger.Info(fmt.Sprintf("Server started on port %d", s.port))

	return http.Serve(listener, nil)
}

func (s *Server) Stop() error {
	if s.listener != nil {
		return s.listener.Close()
	}
	return nil
}

func (s *Server) Port() int {
	return s.port
}

func (s *Server) handleIndex(w http.ResponseWriter, r *http.Request) {
	tmpl, err := template.ParseFiles("web/templates/index.html")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	tmpl.Execute(w, nil)
}
