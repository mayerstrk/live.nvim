package main

import (
	"os"
	"os/signal"
	"syscall"

	"github.com/mayerstrk/live.nvim/server/internal/server"
	"github.com/mayerstrk/live.nvim/server/internal/utils"
)

func main() {
	logger := utils.NewLogger()
	s := server.New(logger)

	go func() {
		if err := s.Start(); err != nil {
			logger.Fatal("Failed to start server:", err)
		}
	}()

	// Handle graceful shutdown
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, syscall.SIGTERM)
	<-c

	logger.Info("Shutting down server...")
	if err := s.Stop(); err != nil {
		logger.Error("Error during server shutdown:", err)
	}
}
