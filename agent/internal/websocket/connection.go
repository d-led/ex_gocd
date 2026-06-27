// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package websocket

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/d-led/ex_gocd/agent/internal/config"
	agentlog "github.com/d-led/ex_gocd/agent/internal/log"
	"github.com/d-led/ex_gocd/agent/pkg/protocol"
	"github.com/gorilla/websocket"
)

// Connection wraps the WebSocket connection and handles message routing
type Connection struct {
	conn   *websocket.Conn
	config *config.Config
	cookie string

	// Channels
	send    chan *protocol.Message
	receive chan *protocol.Message
	done    chan struct{}
}

// Connect establishes a WebSocket connection to the server
func Connect(ctx context.Context, cfg *config.Config, tlsConfig *tls.Config) (*Connection, error) {
	wsURL := cfg.WebSocketURL()

	dialer := websocket.Dialer{
		TLSClientConfig:  tlsConfig,
		HandshakeTimeout: 45 * time.Second,
	}

	// Set required headers for GoCD WebSocket handshake
	header := http.Header{}
	header.Set("Origin", cfg.ServerURL.String())
	header.Set("User-Agent", "GoCD Agent")

	agentlog.Logger.Info().Str("url", wsURL).Msg("Connecting to WebSocket")
	conn, resp, err := dialer.DialContext(ctx, wsURL, header)
	if err != nil {
		if resp != nil {
			agentlog.Logger.Info().Int("status", resp.StatusCode).Msg("WebSocket handshake failed")
			bodyBytes := make([]byte, 1024)
			n, _ := resp.Body.Read(bodyBytes)
			agentlog.Logger.Info().Str("body", string(bodyBytes[:n])).Msg("WebSocket handshake response")
		}
		return nil, fmt.Errorf("failed to connect to %s: %w", wsURL, err)
	}

	agentlog.Logger.Info().Msg("WebSocket handshake successful")
	c := &Connection{
		conn:    conn,
		config:  cfg,
		send:    make(chan *protocol.Message, 10),
		receive: make(chan *protocol.Message, 10),
		done:    make(chan struct{}),
	}

	// Start message pump goroutines
	go c.readPump()
	go c.writePump()

	return c, nil
}

// Send queues a message to be sent. Returns error if connection is closed
// or send buffer is full (backpressure).
func (c *Connection) Send(msg *protocol.Message) error {
	select {
	case c.send <- msg:
		return nil
	case <-c.done:
		return fmt.Errorf("connection closed")
	default:
		return fmt.Errorf("send buffer full")
	}
}

// Receive returns the receive channel
func (c *Connection) Receive() <-chan *protocol.Message {
	return c.receive
}

// Close closes the WebSocket connection
func (c *Connection) Close() error {
	close(c.done)
	return c.conn.Close()
}

// SetCookie stores the session cookie from server
func (c *Connection) SetCookie(cookie string) {
	c.cookie = cookie
}

// readPump reads messages from the WebSocket connection
func (c *Connection) readPump() {
	defer func() {
		if r := recover(); r != nil {
			agentlog.Logger.Info().Interface("panic", r).Msg("Recovered panic in readPump")
		}
	}()
	defer close(c.receive)

	c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		select {
		case <-c.done:
			return
		default:
		}

		var msg protocol.Message
		err := c.conn.ReadJSON(&msg)
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				agentlog.Logger.Info().Err(err).Msg("WebSocket read error")
			}
			return
		}

		// Send ACK for messages that request it
		if msg.AckId != "" {
			if err := c.Send(protocol.AckMessage(msg.AckId)); err != nil {
				// Log dropped ACK — server will resend, this is non-fatal
				fmt.Printf("[websocket] dropped ack %s: %v\n", msg.AckId, err)
			}
		}

		select {
		case c.receive <- &msg:
		case <-c.done:
			return
		}
	}
}

// writePump writes messages to the WebSocket connection
func (c *Connection) writePump() {
	defer func() {
		if r := recover(); r != nil {
			agentlog.Logger.Info().Interface("panic", r).Msg("Recovered panic in writePump")
		}
	}()
	ticker := time.NewTicker(54 * time.Second) // Ping server periodically
	defer ticker.Stop()

	for {
		select {
		case msg, ok := <-c.send:
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.conn.WriteJSON(msg); err != nil {
				agentlog.Logger.Info().Err(err).Msg("WebSocket write error")
				return
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}

		case <-c.done:
			return
		}
	}
}

// MarshalMessage converts a message to JSON for debugging
func MarshalMessage(msg *protocol.Message) string {
	data, _ := json.MarshalIndent(msg, "", "  ")
	return string(data)
}
